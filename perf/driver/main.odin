package main

// One fresh process/log per trial. run.py owns the matrix, deadlines and files.
import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import rifle "rifle:rifle"

Config :: struct {
	workload: string,
	record_bytes, threads, batch_records: int,
	work_bytes, dataset_bytes, cache_bytes, page_bytes, file_bytes: i64,
	checkpoint_bytes: i64,
	sample_every: int,
	read_percent: int,
	seed: u64,
	log_path: string,
}

Latency :: struct {
	samples: int,
	p50_ns, p95_ns, p99_ns: i64,
}

Result :: struct {
	elapsed_ns: i64,
	read_calls, write_calls, read_records, write_records: i64,
	checkpoint_calls: int,
	read_latency, write_latency, checkpoint_latency: Latency,
	verified: bool,
}

Worker :: struct {
	log: ^rifle.Log,
	cfg: ^Config,
	ready, start: ^sync.Sema,
	epoch: ^time.Tick,
	done: i32,
	id: int,
	first, count, dataset_records: i64,
	read_calls, write_calls, read_records, write_records: i64,
	finished_ns: i64,
	read_samples, write_samples: [dynamic]i64,
	last_write_index, last_write_sequence, last_write_count: i64,
}

fail :: proc(message: string) -> ! {
	fmt.eprintln(message)
	os.exit(1)
}

check :: proc(err: rifle.RifleError) {
	if err != nil {
		fmt.eprintfln("log API failed: %v", err)
		os.exit(1)
	}
}

elapsed :: proc(start: time.Tick) -> i64 {return i64(time.tick_since(start))}

// Local generators keep access choices reproducible and avoid a shared RNG lock.
random :: proc(state: ^u64) -> u64 {
	x := state^
	x ~= x << 13
	x ~= x >> 7
	x ~= x << 17
	state^ = x
	return x
}

put_u64 :: proc(dst: []u8, value: u64) {
	v := value
	copy(dst[:8], mem.ptr_to_bytes(&v))
}

get_u64 :: proc(src: []u8) -> u64 {
	v: u64
	copy(mem.ptr_to_bytes(&v), src[:8])
	return v
}

fill_payload :: proc(buf: []u8, record_bytes: int) {
	for &b, i in buf {b = u8((i % record_bytes * 31 + 17) % 251)}
}

stamp :: proc(buf: []u8, record_bytes: int, owner: int, first, count: i64) {
	for i in 0 ..< count {
		record := buf[int(i) * record_bytes:][:record_bytes]
		put_u64(record, u64(first + i + 1))
		put_u64(record[8:], u64(owner))
	}
}

verify_record :: proc(record: []u8, owner: int, sequence: i64) {
	if get_u64(record) != u64(sequence + 1) || get_u64(record[8:]) != u64(owner) {
		fail("record verification failed: sequence or writer ID mismatch")
	}
	for b, i in record[16:] {
		if b != u8(((i + 16) * 31 + 17) % 251) {fail("record verification failed: payload mismatch")}
	}
}

poll :: proc(log: ^rifle.Log) {
	_, err := rifle.log_poll(log)
	check(err)
}

checkpoint :: proc(log: ^rifle.Log) -> i64 {
	start := time.tick_now()
	target := rifle.log_sync(log)
	// Log currently exposes the completion watermark as a field, not an accessor.
	for sync.atomic_load(&log.durable_index.value) < target {poll(log)}
	return elapsed(start)
}

seed_log :: proc(log: ^rifle.Log, cfg: ^Config, records: i64) {
	batch := min(i64(cfg.batch_records), records)
	buf := make([]u8, int(batch) * cfg.record_bytes)
	defer delete(buf)
	fill_payload(buf, cfg.record_bytes)
	for first: i64 = 0; first < records; {
		n := min(batch, records - first)
		stamp(buf, cfg.record_bytes, 0, first, n)
		index, err := rifle.log_write(log, buf[:int(n) * cfg.record_bytes], n)
		check(err)
		if index != first {fail("non-contiguous seed append")}
		poll(log)
		first += n
	}
	_ = checkpoint(log)
}

worker_main :: proc(t: ^thread.Thread) {
	w := cast(^Worker)t.data
	cfg := w.cfg
	batch := i64(1)
	if cfg.workload == "batch" || cfg.workload == "scan" || cfg.workload == "checkpoint" {
		batch = i64(cfg.batch_records)
	}
	buf := make([]u8, int(batch) * cfg.record_bytes)
	defer delete(buf)
	fill_payload(buf, cfg.record_bytes)
	// Allocate samples before releasing the gate; there is no growth in the loop.
	// One call per record is an upper bound, including truncated scan batches.
	capacity := int(w.count)
	sample_every := cfg.sample_every
	if cfg.workload == "checkpoint" {sample_every = 0}
	if sample_every > 0 {capacity = capacity / sample_every + 2} else {capacity = 0}
	w.read_samples = make([dynamic]i64, 0, capacity)
	w.write_samples = make([dynamic]i64, 0, capacity)
	rng := cfg.seed + u64(w.id + 1) * 0x9e3779b97f4a7c15
	if rng == 0 {rng = 1}
	call: i64
	sync.sema_post(w.ready)
	sync.sema_wait(w.start)
	for completed: i64 = 0; completed < w.count; {
		n := min(batch, w.count - completed)
		writing := cfg.workload == "append" || cfg.workload == "batch" || cfg.workload == "checkpoint"
		if cfg.workload == "mixed" {writing = random(&rng) % 100 >= u64(cfg.read_percent)}
		index: i64
		if writing {
			stamp(buf, cfg.record_bytes, w.id + 1, w.first + completed, n)
		} else if cfg.workload == "scan" {
			begin := w.dataset_records * i64(w.id) / i64(cfg.threads)
			end := w.dataset_records * i64(w.id + 1) / i64(cfg.threads)
			index = begin + completed % (end - begin)
			n = min(n, end - index)
		} else {
			index = i64(random(&rng) % u64(w.dataset_records))
		}
		sampled := sample_every > 0 && call % i64(max(sample_every, 1)) == i64(w.id % max(sample_every, 1))
		tick: time.Tick
		if sampled {tick = time.tick_now()}
		data := buf[:int(n) * cfg.record_bytes]
		if writing {
			idx, err := rifle.log_write(w.log, data, n)
			if sampled {append(&w.write_samples, elapsed(tick))}
			check(err)
			w.last_write_index, w.last_write_sequence, w.last_write_count = idx, w.first + completed, n
			w.write_calls += 1
			w.write_records += n
		} else {
			err := rifle.log_read(w.log, data, index, n)
			if sampled {append(&w.read_samples, elapsed(tick))}
			check(err)
			// Cheap bounds/content checks also prevent reads from becoming dead work.
			if get_u64(data) != u64(index + 1) || get_u64(data[int(n - 1) * cfg.record_bytes:]) != u64(index + n) {
				fail("read verification failed")
			}
			w.read_calls += 1
			w.read_records += n
		}
		completed += n
		call += 1
	}
	w.finished_ns = elapsed(w.epoch^)
	sync.atomic_store(&w.done, 1)
}

latency :: proc(samples: []i64) -> Latency {
	if len(samples) == 0 {return {}}
	slice.sort(samples)
	n := len(samples)
	return {n, samples[(n - 1) * 50 / 100], samples[(n - 1) * 95 / 100], samples[(n - 1) * 99 / 100]}
}

run :: proc(log: ^rifle.Log, cfg: ^Config, total, dataset_records: i64) -> Result {
	workers := make([]Worker, cfg.threads)
	threads := make([]^thread.Thread, cfg.threads)
	defer delete(workers)
	defer delete(threads)
	ready, start: sync.Sema
	epoch: time.Tick
	for &w, i in workers {
		first := total * i64(i) / i64(cfg.threads)
		end := total * i64(i + 1) / i64(cfg.threads)
		w = {log = log, cfg = cfg, ready = &ready, start = &start, epoch = &epoch, id = i,
			first = first, count = end - first, dataset_records = dataset_records}
		threads[i] = thread.create(worker_main)
		if threads[i] == nil {fail("could not create worker")}
		threads[i].data = &w
		thread.start(threads[i])
	}
	for _ in workers {sync.sema_wait(&ready)}
	epoch = time.tick_now()
	sync.sema_post(&start, cfg.threads)
	for {
		done := true
		for &w in workers {if sync.atomic_load(&w.done) == 0 {done = false}}
		if done {break}
		poll(log)
	}
	result: Result
	if cfg.workload == "checkpoint" {
		// Checkpoint before any verification reads can advance IO outside timing.
		duration := checkpoint(log)
		result.elapsed_ns = elapsed(epoch)
		result.checkpoint_calls = 1
		result.checkpoint_latency = {1, duration, duration, duration}
	}
	reads, writes: [dynamic]i64
	defer delete(reads)
	defer delete(writes)
	for &w, i in workers {
		thread.join(threads[i])
		thread.destroy(threads[i])
		result.elapsed_ns = max(result.elapsed_ns, w.finished_ns)
		result.read_calls += w.read_calls
		result.write_calls += w.write_calls
		result.read_records += w.read_records
		result.write_records += w.write_records
		append(&reads, ..w.read_samples[:])
		append(&writes, ..w.write_samples[:])
		delete(w.read_samples)
		delete(w.write_samples)
	}
	result.read_latency = latency(reads[:])
	result.write_latency = latency(writes[:])
	// Full payload verification of each writer's final batch, outside timing.
	buf := make([]u8, cfg.record_bytes)
	defer delete(buf)
	for w in workers {
		if w.write_calls == 0 {continue}
		for j in 0 ..< w.last_write_count {
			check(rifle.log_read(log, buf, w.last_write_index + j, 1))
			verify_record(buf, w.id + 1, w.last_write_sequence + j)
		}
	}
	result.verified = true
	return result
}

main :: proc() {
	if len(os.args) != 2 {fail("usage: rifle-perf <config.json> (normally invoked by perf/run.py)")}
	data, read_err := os.read_entire_file(os.args[1], context.allocator)
	if read_err != nil {fail("cannot read benchmark config")}
	defer delete(data)
	cfg: Config
	if err := json.unmarshal(data, &cfg); err != nil {fail("invalid benchmark config")}
	if cfg.record_bytes < 16 || cfg.threads < 1 || cfg.batch_records < 1 || cfg.work_bytes < i64(cfg.record_bytes * cfg.threads) || cfg.sample_every < 0 {
		fail("invalid benchmark sizes")
	}
	if cfg.workload == "mixed" && (cfg.read_percent < 1 || cfg.read_percent > 99) {
		fail("mixed workload requires read_percent between 1 and 99")
	}
	switch cfg.workload {
	case "append", "batch", "scan", "random", "hot", "mixed", "checkpoint":
	case: fail("unknown workload")
	}
	path := strings.clone_to_cstring(cfg.log_path)
	defer delete(path)
	schema, _, schema_err := rifle.schema_create(i64(cfg.record_bytes), []rifle.FieldDesc{
		{name = "sequence", type = .U64}, {name = "writer", type = .U64, offset = 8},
	})
	if schema_err != .None {fail("schema creation failed")}
	defer rifle.schema_destroy(schema)
	config := rifle.DefaultLogConfig
	config.log_path, config.schema = path, schema
	config.cache_size_bytes, config.page_size_bytes = cfg.cache_bytes, cfg.page_bytes
	config.file_size_bytes = cfg.file_bytes
	config.max_open_files = 256
	config.commit_ring_size = 4096
	log, err := rifle.log_init(config, nil)
	check(err)
	// Warmup is at least two cache volumes; read fixtures are larger than cache.
	seed_records := max(cfg.dataset_bytes, 2 * cfg.cache_bytes) / i64(cfg.record_bytes)
	seed_log(log, &cfg, seed_records)
	read_records := seed_records
	if cfg.workload == "hot" {
		read_records = max(i64(1), cfg.cache_bytes / 4 / i64(cfg.record_bytes))
		buf := make([]u8, cfg.record_bytes)
		for i in 0 ..< read_records {check(rifle.log_read(log, buf, i, 1))}
		delete(buf)
	}
	total := cfg.work_bytes / i64(cfg.record_bytes)
	result: Result
	if cfg.workload == "checkpoint" {
		// Group commit: concurrent writers, one coordinator, checkpoint each chunk.
		// Each round has the same worker count. Setup/verification is excluded;
		// elapsed includes writing and waiting for the durable watermark.
		if cfg.checkpoint_bytes < i64(cfg.record_bytes * cfg.threads) {fail("checkpoint chunk too small")}
		chunk := cfg.checkpoint_bytes / i64(cfg.record_bytes)
		samples: [dynamic]i64
		defer delete(samples)
		for first: i64 = 0; first < total; {
			n := min(chunk, total - first)
			round := run(log, &cfg, n, read_records)
			duration := round.checkpoint_latency.p50_ns
			append(&samples, duration)
			result.elapsed_ns += round.elapsed_ns
			result.write_calls += round.write_calls
			result.write_records += round.write_records
			result.checkpoint_calls += 1
			first += n
		}
		result.checkpoint_latency = latency(samples[:])
		result.verified = true
	} else {
		result = run(log, &cfg, total, read_records)
	}
	// Validate part of the original fixture, too, after all timed work.
	buf := make([]u8, cfg.record_bytes)
	defer delete(buf)
	for k: i64 = 0; k < 32; k += 1 {
		index := k * (seed_records - 1) / 31
		check(rifle.log_read(log, buf, index, 1))
		verify_record(buf, 0, index)
	}
	check(rifle.log_deinit(log))
	encoded, encode_err := json.marshal(result)
	if encode_err != nil {fail("result encoding failed")}
	defer delete(encoded)
	fmt.println(string(encoded))
}
