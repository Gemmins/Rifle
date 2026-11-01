package test

import rifle "rifle:rifle"
import "core:mem/virtual"
import "core:sys/linux"
import "core:testing"

@(test)
log_init_rejects_invalid_config :: proc(t: ^testing.T) {
	for case_index in 0 ..< 24 {
		config := rifle.DefaultLogConfig
		config.log_path = "/nonexistent/rifle-config-validation"
		config.record_size = 6
		switch case_index {
		case 0: config.log_path = nil
		case 1: config.log_path = ""
		case 2: config.record_size = 0
		case 3: config.record_size = -1
		case 4: config.page_size_bytes = 0
		case 5: config.page_size_bytes = 2048
		case 6: config.page_size_bytes = 6144
		case 7: config.cache_size_bytes = 0
		case 8: config.cache_size_bytes = config.page_size_bytes * 5
		case 9: config.cache_size_bytes = config.page_size_bytes * 2
		case 10: config.file_size_bytes = 0
		case 11: config.file_size_bytes += 1
		case 12: config.max_open_files = 0
		case 13: config.max_open_files = 4097
		case 14: config.commit_ring_size = 0
		case 15: config.commit_ring_size = 3
		case 16: config.page_size_bytes = -4096
		case 17: config.page_size_bytes = 1 << 31
		case 18: config.cache_size_bytes = -1
		case 19: config.cache_size_bytes = config.page_size_bytes * (1 << 25)
		case 20: config.file_size_bytes = -1
		case 21: config.commit_ring_size = -1
		case 22: config.commit_ring_size = 1 << 62
		case 23: config.cache_size_bytes = config.page_size_bytes / 2
		}
		// Invalid configuration must be rejected before trying to open the path.
		log, err := rifle.log_init(config, nil)
		testing.expect(t, log == nil)
		testing.expect(t, err == .InvalidArgError)
	}
}

@(test)
log_init_missing_directory :: proc(t: ^testing.T) {
	config := rifle.DefaultLogConfig
	// /dev/null is a file, so resolving a child must fail without touching IO setup.
	config.log_path = "/dev/null/rifle"
	config.record_size = 6
	config.cache_size_bytes = 4 * config.page_size_bytes
	config.commit_ring_size = 1
	config.max_open_files = 1
	log, err := rifle.log_init(config, nil)
	testing.expect(t, log == nil)
	testing.expect(t, err == .FileOperationError)
}

@(test)
log_init_reopen_unimplemented :: proc(t: ^testing.T) {
	log, err := rifle.log_init({}, "existing.rfl")
	testing.expect(t, log == nil)
	testing.expect(t, err == .UnimplementedError)
}

// Exercise the shared initialization with a real page cache and fake IO.
// This checks cache wiring without requiring io_uring or disk writes.
@(test)
log_init_cache_and_ring :: proc(t: ^testing.T) {
	f: Fake_IO
	l: rifle.Log
	l.config = rifle.DefaultLogConfig
	l.config.log_path = "/tmp/rifle-log-unit"
	l.config.cache_size_bytes = 4 * l.config.page_size_bytes
	l.config.record_size = 6
	l.config.commit_ring_size = 4
	l.record_size = l.config.record_size
	l.io = fake_io(&f)
	l.cache = rifle.new_page_cache()
	err := rifle.__log_init(&l)
	defer l.cache.deinit(l.cache.data)
	defer delete(l.commit_ring)
	if !testing.expect(t, err == nil) {return}
	pc := cast(^rifle.PageCache)l.cache.data
	testing.expect_value(t, pc.record_size, l.config.record_size)
	testing.expect_value(t, pc.page_size, l.config.page_size_bytes)
	testing.expect_value(t, pc.pages_per_file, l.config.file_size_bytes / l.config.page_size_bytes)
	testing.expect(t, pc.durable_index == &l.durable_index.value)
	testing.expect_value(t, pc.base_path, string(l.config.log_path))
	testing.expect(t, raw_data(f.cache_buffer) == raw_data(pc.pageData))
	testing.expect_value(t, len(f.cache_buffer), int(l.config.cache_size_bytes))
	testing.expect_value(t, l.commit_mask, u64(3))
	for slot in l.commit_ring {testing.expect_value(t, slot.value, i64(-1))}

	// Six-byte records straddle the page boundary; the batch also wraps the ring.
	data := make([]u8, 1500 * 6)
	defer delete(data)
	for &b, i in data {b = u8(i % 251)}
	index, write_err := rifle.log_write(&l, data, 1500)
	testing.expect(t, write_err == nil)
	testing.expect_value(t, index, i64(0))
	testing.expect_value(t, l.visible_index.value, i64(1500))
	testing.expect_value(t, l.durable_index.value, i64(0))
	readback := make([]u8, len(data))
	defer delete(readback)
	testing.expect(t, rifle.log_read(&l, readback, 0, 1500) == nil)
	for b, i in readback {
		if !testing.expect_value(t, b, data[i]) {break}
	}
	testing.expect(t, rifle.log_read(&l, readback[:6], 1500, 1) == .IndexOutOfBoundsError)
}

@(test)
log_deinit_bootstrapped_arena :: proc(t: ^testing.T) {
	l, alloc_err := virtual.arena_growing_bootstrap_new(rifle.Log, "arena", 1 << 16)
	if !testing.expect(t, alloc_err == nil) {return}
	fd, open_err := linux.open("/tmp", {.DIRECTORY, .PATH}, {})
	if !testing.expect(t, open_err == nil) {
		arena := l.arena
		virtual.arena_destroy(&arena)
		return
	}
	l.dirfd = fd
	cache_deinitialized := false
	l.cache.data = &cache_deinitialized
	l.cache.deinit = proc(ctx: rawptr) { (cast(^bool)ctx)^ = true }
	testing.expect(t, rifle.log_deinit(l) == nil)
	testing.expect(t, cache_deinitialized)
}
