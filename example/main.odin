package main

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"
import rifle "rifle:rifle"

RECORD_SIZE :: 8
PAGE_SIZE_BYTES :: #config(PAGE_SIZE_BYTES, 1 << 14)
CACHE_SIZE_BYTES :: #config(CACHE_SIZE_BYTES, 1 << 26)
FILE_SIZE_BYTES :: #config(FILE_SIZE_BYTES, 1 << 28)
MAX_OPEN_FILES :: 64
COMMIT_RING_SIZE :: #config(COMMIT_RING_SIZE, 1 << 8)
RECORDS_PER_THREAD :: #config(RECORDS_PER_THREAD, 1 << 26)
N_THREADS :: #config(N_THREADS, 2)
WRITE_BATCH_SIZE :: #config(WRITE_BATCH_SIZE, 1) // Records per write call
READ_BATCH_SIZE :: #config(READ_BATCH_SIZE, 1 << 12) // Records per read call

#assert(N_THREADS > 0 && RECORDS_PER_THREAD > 0)
#assert(WRITE_BATCH_SIZE > 0 && READ_BATCH_SIZE > 0)

Thread_Data :: struct {
	m:           ^rifle.Log,
	append_errs: int,
}

write_thread :: proc(t: ^thread.Thread) {
	data := cast(^Thread_Data)t.data
	a, _ := runtime.make_aligned([]u8, RECORD_SIZE * min(WRITE_BATCH_SIZE, RECORDS_PER_THREAD), RECORD_SIZE)
	defer delete(a)
	append_errs := 0
	for first := 0; first < RECORDS_PER_THREAD; {
		batch := min(WRITE_BATCH_SIZE, RECORDS_PER_THREAD - first)
		for j in 0 ..< batch {
			(cast(^i64)&a[j * RECORD_SIZE])^ = i64(first + j)
		}
		_, err := rifle.log_write(data.m, a[:batch * RECORD_SIZE], i64(batch))
		if err != nil {
			append_errs += 1
		}
		first += batch
	}
	if append_errs > 0 {
		fmt.println("[writer] append errors:", append_errs)
	}
	data.append_errs = append_errs
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
	fmt.println("write:", end - start)

	fmt.println("head after writes:", sync.atomic_load(&l.visible_index.value))

	total_records := n * RECORDS_PER_THREAD
	a, _ := runtime.make_aligned([]u8, RECORD_SIZE * min(READ_BATCH_SIZE, total_records), RECORD_SIZE)
	defer delete(a)
	start = time.now()._nsec
	count: i64 = 0
	read_errs := 0
	zero_reads := 0
	for first := 0; first < total_records; {
		batch := min(READ_BATCH_SIZE, total_records - first)
		for j in 0 ..< batch {
			(cast(^i64)&a[j * RECORD_SIZE])^ = -1
		}
		err := rifle.log_read(l, a[:batch * RECORD_SIZE], i64(first), i64(batch))
		first += batch
		if err != nil {
			read_errs += 1
			continue
		}
		for j in 0 ..< batch {
			value := (cast(^i64)&a[j * RECORD_SIZE])^
			if value == 0 do zero_reads += 1
			count += value
		}
	}
	end = time.now()._nsec
	fmt.println("read: ", end - start)
	fmt.println("read errs:", read_errs)
	fmt.println("zero reads:", zero_reads)

	per_thread_sum := i64(RECORDS_PER_THREAD) * i64(RECORDS_PER_THREAD - 1) / 2
	expected := i64(n) * per_thread_sum
	fmt.println("sum:     ", count)
	fmt.println("expected:", expected)
	for data in thread_data {
		if data.append_errs != 0 {return false}
	}
	return read_errs == 0 && count == expected && zero_reads == n && sync.atomic_load(&l.visible_index.value) == i64(total_records)
}

main :: proc() {
	// Cache filenames must be absolute when IO also uses the log directory's fd.
	base_path, base_err := os.get_absolute_path("./example", context.allocator)
	if base_err != nil {
		fmt.eprintfln("Error resolving log directory: %v", base_err)
		os.exit(1)
	}
	defer delete(base_path)
	// Use a fresh directory: reopening an existing log is not implemented yet.
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
	config.record_size = RECORD_SIZE
	config.page_size_bytes = PAGE_SIZE_BYTES
	config.cache_size_bytes = CACHE_SIZE_BYTES
	config.file_size_bytes = FILE_SIZE_BYTES
	config.max_open_files = MAX_OPEN_FILES
	config.commit_ring_size = COMMIT_RING_SIZE
	l, err := rifle.log_init(config, nil)
	if err != nil {
		fmt.eprintfln("Error creating log: %v", err)
		os.exit(1)
	}
	// Timings cover append/read, not a durability checkpoint.
	ok := bench_multi(l, N_THREADS)
	deinit_err := rifle.log_deinit(l)
	if !ok || deinit_err != nil {
		fmt.eprintfln("Benchmark failed; shutdown error: %v", deinit_err)
		os.exit(1)
	}
}
