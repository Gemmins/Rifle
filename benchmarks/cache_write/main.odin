#+build linux

package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:sync"
import "core:sys/linux"
import "core:sys/linux/uring"
import "core:time"
import rifle "rifle:rifle"

PAGE_SIZE :: 8192
RECORD_SIZE :: 64
MIB :: 1024 * 1024
GIB :: 1024 * MIB

// Single-threaded benchmark accounting, including polls made inside cache.write.
completed_bytes: i64
last_progress: time.Tick
cache_state: ^rifle.PageCache

fail :: proc(message: string) {
	fmt.eprintf("%s\n", message)
	os.exit(1)
}

bench_init :: proc(ctx: rawptr, buffer: []u8) -> rifle.RifleError {
	err := rifle.uring_init(ctx, buffer)
	if err != nil {
		fmt.eprintf("I/O init failed: %v\n", err)
		os.exit(1)
	}
	return err
}

bench_poll :: proc(ctx: rawptr, completions: []rifle.IOCompletion) -> (u32, rifle.RifleError) {
	n, err := rifle.uring_poll(ctx, completions)
	if err != nil {
		fmt.eprintf("I/O poll failed: %v\n", err)
		os.exit(1)
	}
	for ce in completions[:n] {
		if ce.res < 0 {
			fmt.eprintf("%v failed: %d\n", ce.user_data.op, ce.res)
			os.exit(1)
		}
		if ce.user_data.op == .WRITE {
			if ce.res != PAGE_SIZE {fail("Short write")}
			completed_bytes += i64(ce.res)
		}
	}
	now := time.tick_now()
	if n > 0 {last_progress = now}
	if time.tick_diff(last_progress, now) > 60 * time.Second {
		states: [rifle.PageState]int
		for p in cache_state.pages {states[p.state] += 1}
		io := cast(^rifle.UringIO)ctx
		fmt.eprintf("completed_bytes=%d pages=%v sync_pending=%v sync_in_progress=%v sq_ready=%d cq_ready=%d\n",
		            completed_bytes, states, cache_state.sync_pending, cache_state.sync_in_progress,
		            uring.sq_ready(&io.ring), uring.cq_ready(&io.ring))
		fail("No I/O progress for 60 seconds")
	}
	return n, err
}

main :: proc() {
	directory := ""
	total: i64 = 256 * MIB
	capacity: i64 = 64 * MIB
	file_size: i64 = GIB
	batch: i64 = 128
	args := os.args[1:]
	for i := 0; i < len(args); i += 2 {
		if args[i] == "--help" {
			fmt.println("cache-write --dir PATH [--bytes N] [--cache-bytes N] [--file-bytes N] [--batch N]")
			fmt.println("Defaults: 256 MiB data, 64 MiB cache, 1 GiB files, 128 records/batch.")
			fmt.println("Records are 64 bytes; pages are 8 KiB. Sizes are decimal byte counts.")
			return
		}
		if i + 1 == len(args) {fail("Missing option value (see --help)")}
		if args[i] == "--dir" {
			directory = args[i + 1]
			continue
		}
		consumed: int
		value, ok := strconv.parse_i64(args[i + 1], 10, &consumed)
		if !ok || consumed != len(args[i + 1]) || value <= 0 {fail("Expected a positive integer")}
		switch args[i] {
		case "--bytes": total = value
		case "--cache-bytes": capacity = value
		case "--file-bytes": file_size = value
		case "--batch": batch = value
		case: fail("Unknown option (see --help)")
		}
	}
	if directory == "" {fail("Provide --dir on the filesystem to benchmark")}
	if total % PAGE_SIZE != 0 || file_size % PAGE_SIZE != 0 {fail("Data and file sizes must be page multiples")}
	if capacity % (PAGE_SIZE * rifle.SET_ASSOC) != 0 {fail("Cache size must be a multiple of 32768 bytes")}
	if total <= capacity {fail("Data must be larger than the cache")}
	if batch > PAGE_SIZE / RECORD_SIZE {fail("Batch must be between 1 and 128 records")}
	file_count := (total - 1) / file_size + 1
	if file_count > 16 {fail("At most 16 files supported: sync needs two SQEs per file in the 32-entry ring")}

	dir, dir_err := os.make_directory_temp(directory, "rifle-bench-*", context.allocator)
	if dir_err != nil {fail("Could not create benchmark directory")}
	defer delete(dir)
	defer os.remove_all(dir)
	fmt.printf("path=%s bytes=%d cache_bytes=%d file_bytes=%d batch=%d\n", dir, total, capacity, file_size, batch)

	durable: i64 = -1
	io := rifle.new_uring_io({uring.DEFAULT_PARAMS, u16(file_count), u64(file_size)}, linux.AT_FDCWD)
	io.init = bench_init
	io.poll = bench_poll
	c := rifle.new_page_cache()
	if c.init(c.data, capacity, PAGE_SIZE, io, dir, file_size, &durable) != nil {fail("Cache allocation failed")}
	defer c.deinit(c.data)
	pc := cast(^rifle.PageCache)c.data
	cache_state = pc
	pc.record_size = RECORD_SIZE
	buffer := make([]u8, int(batch * RECORD_SIZE))
	defer delete(buffer)
	seed: u64 = 123456789
	for &b in buffer {
		seed ~= seed << 13
		seed ~= seed >> 7
		seed ~= seed << 17
		b = u8(seed)
	}

	records := total / RECORD_SIZE
	start := time.tick_now()
	last_progress = start
	for index: i64 = 0; index < records; index += batch {
		count := min(batch, records - index)
		c.write(c.data, buffer[:count * RECORD_SIZE], index, count)
	}
	for completed_bytes < total {c.poll(c.data)}
	write_end := time.tick_now()
	if completed_bytes != total {fail("Unexpected completed byte count")}
	c.sync(c.data, records)
	for sync.atomic_load(&durable) != records {c.poll(c.data)}
	sync_end := time.tick_now()
	seconds := f64(time.tick_diff(start, write_end)) / f64(time.Second)
	sync_ms := f64(time.tick_diff(write_end, sync_end)) / f64(time.Millisecond)
	fmt.printf("records=%d completed_bytes=%d seconds=%.6f records/s=%.0f GiB/s=%.3f sync_ms=%.3f\n",
	           records, completed_bytes, seconds, f64(records) / seconds, f64(total) / GIB / seconds, sync_ms)
}
