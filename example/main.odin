package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import rifle "rifle:rifle"

PAYLOAD_SIZE :: #config(PAYLOAD_SIZE, 8) // Bytes after the tracking value
RECORD_SIZE :: size_of(i64) + PAYLOAD_SIZE
PAGE_SIZE_BYTES :: #config(PAGE_SIZE_BYTES, 1 << 12)
RING_SIZE_BYTES :: #config(RING_SIZE_BYTES, 1 << 26)
PAGE_CACHE_SIZE_BYTES :: #config(PAGE_CACHE_SIZE_BYTES, 1 << 26)
FILE_SIZE_BYTES :: #config(FILE_SIZE_BYTES, 1 << 32)
MAX_OPEN_FILES :: 64
COMMIT_RING_SIZE :: #config(COMMIT_RING_SIZE, 1 << 8)
RECORDS_PER_THREAD :: #config(RECORDS_PER_THREAD, 1 << 25)
N_THREADS :: #config(N_THREADS, 1) // Write threads
N_READ_THREADS :: #config(N_READ_THREADS, 1)
WRITE_BATCH_SIZE :: #config(WRITE_BATCH_SIZE, 1) // Records per write call
READ_BATCH_SIZE :: #config(READ_BATCH_SIZE, 1 << 8) // Records per read call
SYNC_INTERVAL :: #config(SYNC_INTERVAL, 1 << 14) // Sync every n records per thread

#assert(N_THREADS > 0 && N_READ_THREADS > 0 && RECORDS_PER_THREAD > 0)
#assert(WRITE_BATCH_SIZE > 0 && READ_BATCH_SIZE > 0)
#assert(PAYLOAD_SIZE > 0 && PAYLOAD_SIZE <= max(u32))

Thread_Data :: struct {
	m:           ^rifle.Log,
	append_errs: int,
}

Read_Thread_Data :: struct {
	m:          ^rifle.Log,
	start:      i64,
	count:      i64,
	sum:        i64,
	read_errs:  int,
	zero_reads: int,
}

write_thread :: proc(t: ^thread.Thread) {
	data := cast(^Thread_Data)t.data
	a := make([]u8, RECORD_SIZE * min(WRITE_BATCH_SIZE, RECORDS_PER_THREAD))
	defer delete(a)
	append_errs := 0
	for first := 0; first < RECORDS_PER_THREAD; {
		batch := min(WRITE_BATCH_SIZE, RECORDS_PER_THREAD - first)
		for j in 0 ..< batch {
			value := i64(first + j)
			copy(a[j * RECORD_SIZE:][:size_of(i64)], mem.ptr_to_bytes(&value))
		}
		_, err := rifle.log_write(data.m, a[:batch * RECORD_SIZE], i64(batch))
		if err != nil {
			append_errs += 1
		}
		first += batch
		// if first % SYNC_INTERVAL == 0 {
		// 	rifle.log_sync(data.m)
		// }
	}
	if append_errs > 0 {
		fmt.println("[writer] append errors:", append_errs)
	}
	data.append_errs = append_errs
}

read_thread :: proc(t: ^thread.Thread) {
	data := cast(^Read_Thread_Data)t.data
	a := make([]u8, RECORD_SIZE * min(i64(READ_BATCH_SIZE), data.count))
	defer delete(a)
	sum: i64
	read_errs, zero_reads := 0, 0
	for first: i64 = 0; first < data.count; {
		batch := min(i64(READ_BATCH_SIZE), data.count - first)
		for j: i64 = 0; j < batch; j += 1 {
			value := i64(-1)
			copy(a[j * RECORD_SIZE:][:size_of(i64)], mem.ptr_to_bytes(&value))
		}
		err := rifle.log_read(data.m, a[:batch * RECORD_SIZE], data.start + first, batch)
		first += batch
		if err != nil {
			read_errs += 1
			continue
		}
		for j: i64 = 0; j < batch; j += 1 {
			value: i64
			copy(mem.ptr_to_bytes(&value), a[j * RECORD_SIZE:][:size_of(i64)])
			if value == 0 {
				zero_reads += 1
			}
			sum += value
		}
	}
	data.sum = sum
	data.read_errs = read_errs
	data.zero_reads = zero_reads
}

bench_single :: proc(l: ^rifle.Log) {
	_ = bench_multi(l, 1)
}

bench_multi :: proc(l: ^rifle.Log, n: int) -> bool {
	thread_data := make([]Thread_Data, n)
	threads := make([]^thread.Thread, n)
	defer delete(thread_data)
	defer delete(threads)

	for i in 0 ..< n {
		thread_data[i] = {
			m = l,
		}
	}

	start := time.now()._nsec
	for i in 0 ..< n {
		t := thread.create(write_thread)
		t.data = &thread_data[i]
		threads[i] = t
		thread.start(t)
	}
	for t in threads {
		thread.join(t)
		thread.destroy(t)
	}
	end := time.now()._nsec
	total_records := i64(n) * RECORDS_PER_THREAD
	seconds := f64(end - start) / 1e9
	fmt.printf(
		"write (%d threads): %.3f ms, %.2f Mrecords/s, %.2f GiB/s\n",
		n,
		seconds * 1e3,
		f64(total_records) / seconds / 1e6,
		f64(total_records) * RECORD_SIZE / seconds / (1 << 30),
	)

	fmt.println("head after writes:", sync.atomic_load(&l.visible_index.value))

	read_data := make([]Read_Thread_Data, N_READ_THREADS)
	read_threads := make([]^thread.Thread, N_READ_THREADS)
	defer delete(read_data)
	defer delete(read_threads)
	for &data, i in read_data {
		first := total_records * i64(i) / N_READ_THREADS
		last := total_records * i64(i + 1) / N_READ_THREADS
		data = {
			m     = l,
			start = first,
			count = last - first,
		}
	}

	start = time.now()._nsec
	for i in 0 ..< N_READ_THREADS {
		t := thread.create(read_thread)
		t.data = &read_data[i]
		read_threads[i] = t
		thread.start(t)
	}
	for t in read_threads {
		thread.join(t)
		thread.destroy(t)
	}
	end = time.now()._nsec
	seconds = f64(end - start) / 1e9
	fmt.printf(
		"read (%d threads): %.3f ms, %.2f Mrecords/s, %.2f GiB/s\n",
		N_READ_THREADS,
		seconds * 1e3,
		f64(total_records) / seconds / 1e6,
		f64(total_records) * RECORD_SIZE / seconds / (1 << 30),
	)
	count: i64
	read_errs, zero_reads := 0, 0
	for data in read_data {
		count += data.sum
		read_errs += data.read_errs
		zero_reads += data.zero_reads
	}
	fmt.println("read errs:", read_errs)
	fmt.println("zero reads:", zero_reads)

	per_thread_sum := i64(RECORDS_PER_THREAD) * i64(RECORDS_PER_THREAD - 1) / 2
	expected := i64(n) * per_thread_sum
	fmt.println("sum:     ", count)
	fmt.println("expected:", expected)
	for data in thread_data {
		if data.append_errs != 0 {
			return false
		}
	}
	return read_errs == 0 && count == expected && zero_reads == n && sync.atomic_load(&l.visible_index.value) == i64(total_records)
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

	schema, bad_field, schema_err := rifle.schema_create(
		RECORD_SIZE,
		[]rifle.FieldDesc{{name = "value", type = .I64}, {name = "payload", type = .Bytes, offset = size_of(i64), size = PAYLOAD_SIZE}},
	)
	if schema_err != .None {
		fmt.eprintfln("Error creating record schema (field %v): %v", bad_field, schema_err)
		os.exit(1)
	}
	defer rifle.schema_destroy(schema)

	config := rifle.DefaultLogConfig
	config.log_path = cpath
	config.schema = schema
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
	ok := bench_multi(l, N_THREADS)
	deinit_err := rifle.log_deinit(l)
	if !ok || deinit_err != nil {
		fmt.eprintfln("Benchmark failed; shutdown error: %v", deinit_err)
		os.exit(1)
	}
}
