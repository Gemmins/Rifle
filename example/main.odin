package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"
import "core:sync"
import "core:sys/linux"
import "core:thread"
import "core:time"
import rifle "rifle:rifle"

PAYLOAD_SIZE :: #config(PAYLOAD_SIZE, 8) // Bytes after timestamp; first 4 store TSC_AUX
RECORD_SIZE :: size_of(u64) + PAYLOAD_SIZE
PAGE_SIZE_BYTES :: #config(PAGE_SIZE_BYTES, 1 << 12)
RING_SIZE_BYTES :: #config(RING_SIZE_BYTES, 1 << 24)
PAGE_CACHE_SIZE_BYTES :: #config(PAGE_CACHE_SIZE_BYTES, 1 << 23)
FILE_SIZE_BYTES :: #config(FILE_SIZE_BYTES, 1 << 30)
MAX_OPEN_FILES :: 64
COMMIT_RING_SIZE :: #config(COMMIT_RING_SIZE, 1 << 8)
MESSAGES_PER_THREAD :: #config(MESSAGES_PER_THREAD, 10_000)
N_THREADS :: #config(N_THREADS, 4) // Independent sender threads
SEND_INTERVAL_US :: #config(SEND_INTERVAL_US, 100)
SEND_INTERVAL :: time.Duration(SEND_INTERVAL_US) * time.Microsecond
DETAILED_LATENCY_DIAGNOSTICS :: #config(DETAILED_LATENCY_DIAGNOSTICS, false)
PIN_THREADS :: #config(PIN_THREADS, false)
AFFINITY_CPU_OFFSET :: #config(AFFINITY_CPU_OFFSET, 0) // Ordinal in the process's allowed CPU set
REALTIME_PRIORITY :: #config(REALTIME_PRIORITY, 0) // 0 disables SCHED_FIFO; otherwise 1..99
POLL_INTERVAL_RECORDS :: #config(POLL_INTERVAL_RECORDS, 1 << 10) // Global records between progress polls
TRAILING_READER :: true
N_TRAILING_READERS :: 1
TRAILING_READER_LAG_RECORDS :: 0 // Read as soon as each message becomes visible

#assert(N_THREADS > 0 && MESSAGES_PER_THREAD > 0)
#assert(SEND_INTERVAL_US > 0)
#assert(AFFINITY_CPU_OFFSET >= 0)
#assert(REALTIME_PRIORITY >= 0 && REALTIME_PRIORITY <= 99)
#assert(REALTIME_PRIORITY == 0 || PIN_THREADS)
#assert(POLL_INTERVAL_RECORDS > 0)
#assert(PAYLOAD_SIZE >= size_of(u32) && PAYLOAD_SIZE <= max(u32))
#assert(!TRAILING_READER || N_TRAILING_READERS > 0)
#assert(TRAILING_READER_LAG_RECORDS >= 0)

Timestamp_Kind :: enum {
	Monotonic_Nanoseconds,
	RDTSCP,
}

Timestamp_Source :: struct {
	kind:             Timestamp_Kind,
	ticks_per_second: u64,
}

Write_Diagnostic :: struct {
	valid:           bool,
	sender_thread:   int,
	after_write:     u64,
	after_write_aux: u32,
}

MAX_AFFINITY_CPUS :: 1024

Available_CPUs :: struct {
	ids:   [MAX_AFFINITY_CPUS]int,
	count: int,
}

get_available_cpus :: proc "contextless" () -> (result: Available_CPUs, err: linux.Errno) {
	mask: [MAX_AFFINITY_CPUS / 64]u64
	bytes, affinity_err := linux.sched_getaffinity(0, size_of(mask), &mask)
	if affinity_err != nil {
		return {}, affinity_err
	}
	for word, word_index in mask[:bytes / size_of(u64)] {
		for bit in 0 ..< 64 {
			if word & (u64(1) << uint(bit)) != 0 {
				result.ids[result.count] = word_index * 64 + bit
				result.count += 1
			}
		}
	}
	return result, nil
}

pin_current_thread :: proc "contextless" (cpu_id: int) -> linux.Errno {
	if cpu_id < 0 || cpu_id >= MAX_AFFINITY_CPUS {
		return .EINVAL
	}
	mask: [MAX_AFFINITY_CPUS / 64]u64
	mask[cpu_id / 64] |= u64(1) << uint(cpu_id % 64)
	_, err := linux.sched_setaffinity(0, size_of(mask), &mask)
	return err
}

set_current_thread_realtime :: proc "contextless" (priority: int) -> linux.Errno {
	if priority <= 0 || priority > 99 {
		return .EINVAL
	}
	params := linux.Sched_Param{sched_priority = i32(priority)}
	return linux.sched_setscheduler(0, i32(linux.Sched_Policy.FIFO), &params)
}

Max_Latency_Sample :: struct {
	valid:           bool,
	index:           i64,
	sent:            u64,
	before_read:     u64,
	after_read:      u64,
	send_aux:        u32,
	before_read_aux: u32,
	after_read_aux:  u32,
}

Thread_Data :: struct {
	m:                       ^rifle.Log,
	timestamp_source:        ^Timestamp_Source,
	write_diagnostics:       []Write_Diagnostic,
	id:                      int,
	cpu_id:                  int,
	affinity_err:            linux.Errno,
	scheduler_err:           linux.Errno,
	cancelled:               bool,
	append_errs:             int,
	poll_errs:               int,
	first_poll_err:          rifle.RifleError,
	first_poll_err_attempt:  int,
	first_poll_err_was_final: bool,
	poll_attempts:           int,
	polls_performed:         int,
	poll_ticks_total:        u128,
	poll_ticks_min:          u64,
	poll_ticks_max:          u64,
	sender_aux_changes:      int,
	write_window_migrations: int,
}

Trailing_Reader_Data :: struct {
	m:                 ^rifle.Log,
	timestamp_source:  ^Timestamp_Source,
	latencies:         []u64,
	count:             i64,
	read_count:        i64,
	latency_total:     u128,
	latency_count:     int,
	latency_min:       u64,
	latency_max:       u64,
	max_sample:         Max_Latency_Sample,
	invalid_timestamps: int,
	cross_cpu_samples: int,
	receiver_aux_changes: int,
	read_window_migrations: int,
	read_errs:         int,
	cpu_id:            int,
	affinity_err:      linux.Errno,
	scheduler_err:     linux.Errno,
}

poll_log :: proc(data: ^Thread_Data, final := false) {
	started, _ := timestamp_now(data.timestamp_source)
	polled, err := rifle.log_poll(data.m)
	finished, _ := timestamp_now(data.timestamp_source)
	data.poll_attempts += 1
	if err != nil {
		data.poll_errs += 1
		if data.first_poll_err == nil {
			data.first_poll_err = err
			data.first_poll_err_attempt = data.poll_attempts
			data.first_poll_err_was_final = final
		}
	}
	if !polled || finished < started {
		return
	}
	duration := finished - started
	data.polls_performed += 1
	data.poll_ticks_total += u128(duration)
	if data.polls_performed == 1 {
		data.poll_ticks_min = duration
	} else {
		data.poll_ticks_min = min(data.poll_ticks_min, duration)
	}
	data.poll_ticks_max = max(data.poll_ticks_max, duration)
}

write_thread :: proc(t: ^thread.Thread) {
	data := cast(^Thread_Data)t.data
	if data.cancelled {
		return
	}
	when PIN_THREADS {
		data.affinity_err = pin_current_thread(data.cpu_id)
	}
	when REALTIME_PRIORITY > 0 {
		data.scheduler_err = set_current_thread_realtime(REALTIME_PRIORITY)
	}
	message: [RECORD_SIZE]u8
	append_errs := 0
	last_send_aux: u32
	have_send_aux := false
	when !DETAILED_LATENCY_DIAGNOSTICS {
		_ = last_send_aux
		_ = have_send_aux
	}

	// Each sender owns its deadline. There is deliberately no shared clock,
	// barrier, or turn-taking between sender threads.
	next_send := time.tick_now()
	for _ in 0 ..< MESSAGES_PER_THREAD {
		remaining := time.tick_diff(time.tick_now(), next_send)
		if remaining > 0 {
			time.accurate_sleep(remaining)
		}

		timestamp, timestamp_aux := timestamp_now(data.timestamp_source)
		when DETAILED_LATENCY_DIAGNOSTICS {
			if data.timestamp_source.kind == .RDTSCP {
				if have_send_aux && timestamp_aux != last_send_aux {
					data.sender_aux_changes += 1
				}
				last_send_aux = timestamp_aux
				have_send_aux = true
			}
		}
		copy(message[:size_of(u64)], mem.ptr_to_bytes(&timestamp))
		copy(message[size_of(u64):][:size_of(u32)], mem.ptr_to_bytes(&timestamp_aux))
		index, err := rifle.log_write(data.m, message[:], 1)
		when !DETAILED_LATENCY_DIAGNOSTICS {
			_ = index
		}
		when DETAILED_LATENCY_DIAGNOSTICS {
			after_write, after_write_aux := timestamp_now(data.timestamp_source)
			if data.timestamp_source.kind == .RDTSCP && timestamp_aux != after_write_aux {
				data.write_window_migrations += 1
			}
			if err == nil && index >= 0 && index < i64(len(data.write_diagnostics)) {
				data.write_diagnostics[index] = {
					valid           = true,
					sender_thread   = data.id,
					after_write     = after_write,
					after_write_aux = after_write_aux,
				}
			}
		}
		if err != nil {
			append_errs += 1
		}

		next_send = time.tick_add(next_send, SEND_INTERVAL)
		if (index + 1) % POLL_INTERVAL_RECORDS == 0 {
			poll_log(data)
		}
	}
	if append_errs > 0 {
		fmt.println("[writer] append errors:", append_errs)
	}
	// Progress outstanding I/O without requesting durability. Partial-page
	// sync is not implemented yet and is unrelated to this latency example.
	poll_log(data, final = true)
	data.append_errs = append_errs
}

trailing_read_thread :: proc(t: ^thread.Thread) {
	data := cast(^Trailing_Reader_Data)t.data
	when PIN_THREADS {
		data.affinity_err = pin_current_thread(data.cpu_id)
	}
	when REALTIME_PRIORITY > 0 {
		data.scheduler_err = set_current_thread_realtime(REALTIME_PRIORITY)
	}
	record: [RECORD_SIZE]u8
	read_errs := 0
	latency_min := max(u64)
	latency_max: u64
	latency_total: u128
	latency_count, invalid_timestamps, cross_cpu_samples := 0, 0, 0
	receiver_aux_changes, read_window_migrations := 0, 0
	last_receive_aux: u32
	have_receive_aux := false
	when !DETAILED_LATENCY_DIAGNOSTICS {
		_ = last_receive_aux
		_ = have_receive_aux
	}
	max_sample: Max_Latency_Sample
	next, visible: i64
	lag := i64(max(TRAILING_READER_LAG_RECORDS, 1))
	for next < data.count {
		required_visible := min(next + lag, data.count)
		for visible < required_visible {
			visible = sync.atomic_load(&data.m.visible_index.value)
		}

		before_read: u64
		before_read_aux: u32
		when DETAILED_LATENCY_DIAGNOSTICS {
			before_read, before_read_aux = timestamp_now(data.timestamp_source)
		}
		err := rifle.log_read(data.m, record[:], next, 1)
		if err != nil {
			read_errs += 1
			break
		}
		received, receive_aux := timestamp_now(data.timestamp_source)
		when DETAILED_LATENCY_DIAGNOSTICS {
			if data.timestamp_source.kind == .RDTSCP {
				if have_receive_aux && receive_aux != last_receive_aux {
					receiver_aux_changes += 1
				}
				if before_read_aux != receive_aux {
					read_window_migrations += 1
				}
				last_receive_aux = receive_aux
				have_receive_aux = true
			}
		}
		sent: u64
		send_aux: u32
		copy(mem.ptr_to_bytes(&sent), record[:size_of(u64)])
		copy(mem.ptr_to_bytes(&send_aux), record[size_of(u64):][:size_of(u32)])
		if received < sent {
			invalid_timestamps += 1
		} else {
			latency := received - sent
			data.latencies[latency_count] = latency
			if latency_count == 0 || latency > latency_max {
				max_sample = {
					valid           = true,
					index           = next,
					sent            = sent,
					before_read     = before_read,
					after_read      = received,
					send_aux        = send_aux,
					before_read_aux = before_read_aux,
					after_read_aux  = receive_aux,
				}
			}
			latency_count += 1
			latency_total += u128(latency)
			latency_min = min(latency_min, latency)
			latency_max = max(latency_max, latency)
			if data.timestamp_source.kind == .RDTSCP && send_aux != receive_aux {
				cross_cpu_samples += 1
			}
		}
		next += 1
	}
	data.read_count = next
	data.latency_total = latency_total
	data.latency_count = latency_count
	data.latency_min = latency_count > 0 ? latency_min : 0
	data.latency_max = latency_max
	data.max_sample = max_sample
	data.invalid_timestamps = invalid_timestamps
	data.cross_cpu_samples = cross_cpu_samples
	data.receiver_aux_changes = receiver_aux_changes
	data.read_window_migrations = read_window_migrations
	data.read_errs = read_errs
}

bench_single :: proc(l: ^rifle.Log, timestamp_source: ^Timestamp_Source) {
	_ = bench_multi(l, 1, timestamp_source)
}

ticks_to_microseconds :: proc(ticks: f64, source: ^Timestamp_Source) -> f64 {
	return ticks * 1e6 / f64(source.ticks_per_second)
}

timestamp_delta_microseconds :: proc(finished, started: u64, source: ^Timestamp_Source) -> f64 {
	return f64(i128(finished) - i128(started)) * 1e6 / f64(source.ticks_per_second)
}

timestamp_source_name :: proc(source: ^Timestamp_Source) -> string {
	switch source.kind {
	case .RDTSCP:
		return "RDTSCP"
	case .Monotonic_Nanoseconds:
		return "monotonic clock"
	}
	return "unknown"
}

print_max_latency_diagnostic :: proc(
	data: ^Trailing_Reader_Data,
	writes: []Write_Diagnostic,
	timestamp_source: ^Timestamp_Source,
) {
	sample := &data.max_sample
	if !sample.valid {
		return
	}
	fmt.printf(
		"max latency record: index=%d, end-to-end=%.3f us\n",
		sample.index,
		timestamp_delta_microseconds(sample.after_read, sample.sent, timestamp_source),
	)
	if sample.index < 0 || sample.index >= i64(len(writes)) || !writes[sample.index].valid {
		fmt.println("max latency write diagnostic: unavailable")
		return
	}
	write := &writes[sample.index]
	fmt.printf(
		"max latency split: sender=%d, log_write window=%.3f us, after-write->before-read=%.3f us, log_read window=%.3f us\n",
		write.sender_thread,
		timestamp_delta_microseconds(write.after_write, sample.sent, timestamp_source),
		timestamp_delta_microseconds(sample.before_read, write.after_write, timestamp_source),
		timestamp_delta_microseconds(sample.after_read, sample.before_read, timestamp_source),
	)
	if timestamp_source.kind == .RDTSCP {
		fmt.printf(
			"max latency TSC_AUX: send=%d, after-write=%d, before-read=%d, after-read=%d\n",
			sample.send_aux,
			write.after_write_aux,
			sample.before_read_aux,
			sample.after_read_aux,
		)
	}
}

bench_multi :: proc(l: ^rifle.Log, n: int, timestamp_source: ^Timestamp_Source) -> bool {
	thread_data := make([]Thread_Data, n)
	threads := make([]^thread.Thread, n)
	total_records := i64(n) * MESSAGES_PER_THREAD
	write_diagnostics := make([]Write_Diagnostic, int(total_records))
	available_cpus: Available_CPUs
	when !PIN_THREADS {
		_ = available_cpus
	}
	when PIN_THREADS {
		affinity_err: linux.Errno
		available_cpus, affinity_err = get_available_cpus()
		if affinity_err != nil {
			fmt.eprintfln("Error reading allowed CPU affinity set: %v", affinity_err)
			return false
		}
		reader_thread_count := TRAILING_READER ? N_TRAILING_READERS : 0
		needed := AFFINITY_CPU_OFFSET + n + reader_thread_count
		if needed > available_cpus.count {
			fmt.eprintfln(
				"CPU affinity needs %d allowed CPUs after offset %d, but only %d are available",
				n + reader_thread_count,
				AFFINITY_CPU_OFFSET,
				available_cpus.count,
			)
			return false
		}
	}
	defer delete(thread_data)
	defer delete(threads)
	defer delete(write_diagnostics)

	for i in 0 ..< n {
		thread_data[i] = {
			m                 = l,
			timestamp_source  = timestamp_source,
			write_diagnostics = write_diagnostics,
			id                = i,
			cpu_id            = -1,
		}
		when PIN_THREADS {
			thread_data[i].cpu_id = available_cpus.ids[AFFINITY_CPU_OFFSET + i]
			fmt.printf("CPU affinity: writer %d -> CPU %d\n", i, thread_data[i].cpu_id)
		}
	}
	when TRAILING_READER {
		trailing_data: [N_TRAILING_READERS]Trailing_Reader_Data
		trailing_threads: [N_TRAILING_READERS]^thread.Thread
		for &data, i in trailing_data {
			data = {
				m                = l,
				timestamp_source = timestamp_source,
				latencies        = make([]u64, int(total_records)),
				count            = total_records,
				cpu_id           = -1,
			}
			when PIN_THREADS {
				data.cpu_id = available_cpus.ids[AFFINITY_CPU_OFFSET + n + i]
				fmt.printf("CPU affinity: reader %d -> CPU %d\n", i, data.cpu_id)
			}
			t := thread.create(trailing_read_thread)
			if t == nil {
				fmt.eprintfln("Failed to create reader thread %d", i)
				for previous in 0 ..< i {
					trailing_data[previous].count = 0
					thread.destroy(trailing_threads[previous])
				}
				return false
			}
			t.data = &data
			trailing_threads[i] = t
		}
		defer for data in trailing_data {
			delete(data.latencies)
		}
	}
	when REALTIME_PRIORITY > 0 {
		fmt.printf("Worker scheduling: SCHED_FIFO priority %d\n", REALTIME_PRIORITY)
	}
	for i in 0 ..< n {
		t := thread.create(write_thread)
		if t == nil {
			fmt.eprintfln("Failed to create writer thread %d", i)
			for previous in 0 ..< i {
				thread_data[previous].cancelled = true
				thread.destroy(threads[previous])
			}
			when TRAILING_READER {
				for &data, reader_index in trailing_data {
					data.count = 0
					thread.destroy(trailing_threads[reader_index])
				}
			}
			return false
		}
		t.data = &thread_data[i]
		threads[i] = t
	}

	start := time.tick_now()
	when TRAILING_READER {
		for t in trailing_threads {
			thread.start(t)
		}
	}
	for t in threads {
		thread.start(t)
	}
	for t in threads {
		thread.join(t)
	}
	writers_end := time.tick_now()
	when TRAILING_READER {
		for t in trailing_threads {
			thread.join(t)
		}
		readers_end := time.tick_now()
	}
	for t in threads {
		thread.destroy(t)
	}
	when TRAILING_READER {
		for t in trailing_threads {
			thread.destroy(t)
		}
	}
	write_seconds := f64(time.duration_nanoseconds(time.tick_diff(start, writers_end))) / 1e9
	fmt.printf(
		"sent %d messages (%d threads x %d) in %.3f ms, %.2f messages/s; interval=%d us/thread\n",
		total_records,
		n,
		MESSAGES_PER_THREAD,
		write_seconds * 1e3,
		f64(total_records) / write_seconds,
		SEND_INTERVAL_US,
	)
	affinity_ok := true
	when TRAILING_READER {
		reader_seconds := f64(time.duration_nanoseconds(time.tick_diff(start, readers_end))) / 1e9
		reader_records := total_records * N_TRAILING_READERS
		fmt.printf(
			"trailing readers (%d threads): %.3f ms, %.2f Mrecords/s, %.2f GiB/s\n",
			N_TRAILING_READERS,
			reader_seconds * 1e3,
			f64(reader_records) / reader_seconds / 1e6,
			f64(reader_records) * RECORD_SIZE / reader_seconds / (1 << 30),
		)
		read_count: i64
		read_errs := 0
		invalid_timestamps := 0
		readers_ok := true
		for &data, reader_index in trailing_data {
			when PIN_THREADS {
				if data.affinity_err != nil {
					fmt.eprintfln("Reader %d failed to pin to CPU %d: %v", reader_index, data.cpu_id, data.affinity_err)
					affinity_ok = false
				}
			}
			when REALTIME_PRIORITY > 0 {
				if data.scheduler_err != nil {
					fmt.eprintfln("Reader %d failed to set SCHED_FIFO priority %d: %v", reader_index, REALTIME_PRIORITY, data.scheduler_err)
					affinity_ok = false
				}
			}
			read_count += data.read_count
			read_errs += data.read_errs
			invalid_timestamps += data.invalid_timestamps
			readers_ok = readers_ok && data.read_errs == 0 && data.read_count == total_records && data.invalid_timestamps == 0

			if data.latency_count > 0 {
				latencies := data.latencies[:data.latency_count]
				slice.sort(latencies)
				p50 := latencies[(data.latency_count - 1) * 50 / 100]
				p90 := latencies[(data.latency_count - 1) * 90 / 100]
				p99 := latencies[(data.latency_count - 1) * 99 / 100]
				p999 := latencies[(data.latency_count - 1) * 999 / 1000]
				p9999 := latencies[(data.latency_count - 1) * 9_999 / 10_000]
				p99999 := latencies[(data.latency_count - 1) * 99_999 / 100_000]
				average := f64(data.latency_total) / f64(data.latency_count)
				fmt.printf(
					"latency reader %d (%s): min=%.3f us, p50=%.3f us, avg=%.3f us, p90=%.3f us, p99=%.3f us, p99.9=%.3f us, p99.99=%.3f us, p99.999=%.3f us, max=%.3f us\n",
					reader_index,
					timestamp_source_name(timestamp_source),
					ticks_to_microseconds(f64(data.latency_min), timestamp_source),
					ticks_to_microseconds(f64(p50), timestamp_source),
					ticks_to_microseconds(average, timestamp_source),
					ticks_to_microseconds(f64(p90), timestamp_source),
					ticks_to_microseconds(f64(p99), timestamp_source),
					ticks_to_microseconds(f64(p999), timestamp_source),
					ticks_to_microseconds(f64(p9999), timestamp_source),
					ticks_to_microseconds(f64(p99999), timestamp_source),
					ticks_to_microseconds(f64(data.latency_max), timestamp_source),
				)
				when ODIN_ARCH == .amd64 {
					if timestamp_source.kind == .RDTSCP {
						fmt.printf("RDTSCP samples with different send/receive TSC_AUX: %d/%d\n", data.cross_cpu_samples, data.latency_count)
					}
				}
				when DETAILED_LATENCY_DIAGNOSTICS {
					print_max_latency_diagnostic(&data, write_diagnostics, timestamp_source)
					if timestamp_source.kind == .RDTSCP {
						fmt.printf(
							"reader TSC_AUX changes between messages: %d; migrations during log_read: %d\n",
							data.receiver_aux_changes,
							data.read_window_migrations,
						)
					}
				}
			}
		}
		fmt.println("head after writes:       ", sync.atomic_load(&l.visible_index.value))
		fmt.println("trailing read errs:      ", read_errs)
		fmt.println("trailing records:        ", read_count)
		fmt.println("expected reader records: ", total_records * N_TRAILING_READERS)
		fmt.println("invalid timestamps:      ", invalid_timestamps)
	} else {
		fmt.println("head after writes:", sync.atomic_load(&l.visible_index.value))
	}
	poll_attempts, polls_performed, poll_errs := 0, 0, 0
	poll_ticks_total: u128
	poll_ticks_min := max(u64)
	poll_ticks_max: u64
	first_poll_err: rifle.RifleError
	first_poll_err_writer, first_poll_err_attempt := -1, 0
	first_poll_err_was_final := false
	sender_aux_changes, write_window_migrations := 0, 0
	for data in thread_data {
		when PIN_THREADS {
			if data.affinity_err != nil {
				fmt.eprintfln("Writer %d failed to pin to CPU %d: %v", data.id, data.cpu_id, data.affinity_err)
				affinity_ok = false
			}
		}
		when REALTIME_PRIORITY > 0 {
			if data.scheduler_err != nil {
				fmt.eprintfln("Writer %d failed to set SCHED_FIFO priority %d: %v", data.id, REALTIME_PRIORITY, data.scheduler_err)
				affinity_ok = false
			}
		}
		poll_attempts += data.poll_attempts
		polls_performed += data.polls_performed
		poll_errs += data.poll_errs
		if first_poll_err == nil && data.first_poll_err != nil {
			first_poll_err = data.first_poll_err
			first_poll_err_writer = data.id
			first_poll_err_attempt = data.first_poll_err_attempt
			first_poll_err_was_final = data.first_poll_err_was_final
		}
		poll_ticks_total += data.poll_ticks_total
		if data.polls_performed > 0 {
			poll_ticks_min = min(poll_ticks_min, data.poll_ticks_min)
			poll_ticks_max = max(poll_ticks_max, data.poll_ticks_max)
		}
		sender_aux_changes += data.sender_aux_changes
		write_window_migrations += data.write_window_migrations
		if data.append_errs != 0 {
			return false
		}
	}
	if polls_performed > 0 {
		fmt.printf(
			"log_poll: %d performed/%d attempts, min=%.3f us, avg=%.3f us, max=%.3f us, errors=%d\n",
			polls_performed,
			poll_attempts,
			ticks_to_microseconds(f64(poll_ticks_min), timestamp_source),
			ticks_to_microseconds(f64(poll_ticks_total) / f64(polls_performed), timestamp_source),
			ticks_to_microseconds(f64(poll_ticks_max), timestamp_source),
			poll_errs,
		)
	} else {
		fmt.printf("log_poll: 0 performed/%d attempts, errors=%d\n", poll_attempts, poll_errs)
	}
	if first_poll_err != nil {
		fmt.eprintfln(
			"first log_poll error: %v (writer=%d, attempt=%d, final=%v)",
			first_poll_err,
			first_poll_err_writer,
			first_poll_err_attempt,
			first_poll_err_was_final,
		)
	}
	when DETAILED_LATENCY_DIAGNOSTICS {
		if timestamp_source.kind == .RDTSCP {
			fmt.printf(
				"writer TSC_AUX changes between messages: %d; migrations during log_write: %d\n",
				sender_aux_changes,
				write_window_migrations,
			)
		}
	}
	if poll_errs != 0 {
		return false
	}
	if !affinity_ok {
		return false
	}
	when TRAILING_READER {
		return readers_ok && sync.atomic_load(&l.visible_index.value) == total_records
	}
	return sync.atomic_load(&l.visible_index.value) == total_records
}

main :: proc() {
	base_path, base_err := os.get_absolute_path("./example", context.allocator)
	if base_err != nil {
		fmt.eprintfln("Error resolving log directory: %v", base_err)
		os.exit(1)
	}
	defer delete(base_path)
	path, path_err := os.make_directory_temp(base_path, "data-*", context.allocator)
	if path_err != nil {
		fmt.eprintfln("Error creating log directory: %v", path_err)
		os.exit(1)
	}
	defer delete(path)
	cpath, clone_err := strings.clone_to_cstring(path)
	if clone_err != nil {
		fmt.eprintfln("Error copying log path: %v", clone_err)
		os.exit(1)
	}
	defer delete(cpath)
	fmt.println("Log directory:", path)

	config := rifle.DefaultLogConfig
	config.log_path = cpath
	config.schema = {
		record_size = RECORD_SIZE,
		fields      = []rifle.SchemaField{{name = "timestamp", type = .U64}},
	}
	when PAYLOAD_SIZE > 0 {
		config.schema.fields = []rifle.SchemaField {
			{name = "timestamp", type = .U64},
			{name = "payload", type = .Bytes, offset = size_of(u64), size = PAYLOAD_SIZE},
		}
	}
	config.page_size_bytes = PAGE_SIZE_BYTES
	config.ring_size_bytes = RING_SIZE_BYTES
	config.page_cache_size_bytes = PAGE_CACHE_SIZE_BYTES
	config.file_size_bytes = FILE_SIZE_BYTES
	config.max_open_files = MAX_OPEN_FILES
	config.commit_ring_size = COMMIT_RING_SIZE
	l, err := rifle.log_init(config, nil)
	if err != nil {
		fmt.eprintfln("Error creating log: %v", err)
		os.exit(1)
	}
	timestamp_source := timestamp_source_init()
	if timestamp_source.kind == .RDTSCP {
		fmt.printf("Timestamp source: RDTSCP (TSC %.3f MHz)\n", f64(timestamp_source.ticks_per_second) / 1e6)
	} else {
		fmt.println("Timestamp source: monotonic clock (RDTSCP unavailable or TSC is not invariant)")
	}
	ok := bench_multi(l, N_THREADS, &timestamp_source)
	deinit_err := rifle.log_deinit(l)
	if !ok || deinit_err != nil {
		fmt.eprintfln("Benchmark failed; shutdown error: %v", deinit_err)
		os.exit(1)
	}
}
