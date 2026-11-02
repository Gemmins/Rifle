package test

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:thread"
import "core:time"
import rifle "rifle:rifle"

System_Log :: struct {
	log:   ^rifle.Log,
	path:  string,
	cpath: cstring,
}

system_log_cleanup :: proc(ctx: rawptr) {
	s := cast(^System_Log)ctx
	if s.log != nil {
		schema := s.log.config.schema
		rifle.log_deinit(s.log)
		rifle.schema_destroy(schema)
	}
	if len(s.path) > 0 {os.remove_all(s.path)}
	delete(s.cpath)
	delete(s.path)
	free(s)
}

system_log_create :: proc(t: ^testing.T) -> ^System_Log {
	testing.set_fail_timeout(t, 15 * time.Second)
	s := new(System_Log)
	testing.cleanup(t, system_log_cleanup, s)
	working_directory, wd_err := os.get_working_directory(context.allocator)
	extra_require(t, wd_err == nil)
	defer delete(working_directory)
	path, err := os.make_directory_temp(working_directory, ".rifle-system-*", context.allocator)
	extra_require(t, err == nil)
	s.path = path
	cpath, alloc_err := strings.clone_to_cstring(path)
	extra_require(t, alloc_err == nil)
	s.cpath = cpath
	config := rifle.DefaultLogConfig
	config.log_path = cpath
	schema, _, schema_err := rifle.schema_create(8, []rifle.FieldDesc{{name = "value", type = .I64}})
	extra_require(t, schema_err == .None)
	config.schema = schema
	config.page_size_bytes = 4096
	config.cache_size_bytes = 4 * 4096
	config.file_size_bytes = 2 * 4096
	config.commit_ring_size = 8
	config.max_open_files = 16
	l, init_err := rifle.log_init(config, nil)
	extra_require(t, init_err == nil)
	s.log = l
	return s
}

// Public poll/sync forwarding is tested separately with spies. Here use the
// cache interface to isolate the real kernel IO and durable-completion path.
system_drain_and_sync :: proc(t: ^testing.T, l: ^rifle.Log) {
	pc := cast(^rifle.PageCache)l.cache.data
	for {
		_, err := l.cache.poll(l.cache.data)
		extra_require(t, err == nil)
		ready := true
		for p in pc.pages {
			if p.state != .Empty && p.state != .Clean {ready = false}
		}
		if ready {break}
	}
	target := sync.atomic_load(&l.visible_index.value)
	l.cache.sync(l.cache.data, target)
	for sync.atomic_load(&l.durable_index.value) < target {
		_, err := l.cache.poll(l.cache.data)
		extra_require(t, err == nil)
	}
}

@(test)
system_log_cache_uring_eviction_and_file_boundaries :: proc(t: ^testing.T) {
	s := system_log_create(t)
	l := s.log
	// Sixteen pages across eight files, with only four cache slots.
	data: [73]i64
	for first := 0; first < 8192; {
		count := min(len(data), 8192 - first)
		for &v, i in data[:count] {v = i64(first + i + 1)}
		bytes := (cast([^]u8)raw_data(data[:]))[:count * 8]
		index, err := rifle.log_write(l, bytes, i64(count))
		extra_require(t, err == nil)
		testing.expect_value(t, index, i64(first))
		first += count
	}
	testing.expect_value(t, l.visible_index.value, i64(8192))
	testing.expect_value(t, l.durable_index.value, i64(0))
	system_drain_and_sync(t, l)
	testing.expect_value(t, l.durable_index.value, i64(8192))
	readback: [127]i64
	for first := 0; first < 8192; {
		count := min(len(readback), 8192 - first)
		bytes := (cast([^]u8)raw_data(readback[:]))[:count * 8]
		extra_require(t, rifle.log_read(l, bytes, i64(first), i64(count)) == nil)
		for v, i in readback[:count] {extra_require(t, v == i64(first + i + 1))}
		first += count
	}
	// Check actual files as well as reads through the cache.
	for file_id in 0 ..< 8 {
		path := fmt.aprintf("%s/data_%d.rfl", s.path, file_id)
		defer delete(path)
		bytes, err := os.read_entire_file(path, context.allocator)
		extra_require(t, err == nil)
		defer delete(bytes)
		extra_require(t, len(bytes) == 8192)
		values := (cast([^]i64)raw_data(bytes))[:1024]
		for v, i in values {extra_require(t, v == i64(file_id * 1024 + i + 1))}
	}
	path := fmt.aprintf("%s/base.rfl", s.path)
	defer delete(path)
	bytes, err := os.read_entire_file(path, context.allocator)
	extra_require(t, err == nil)
	defer delete(bytes)
	header, header_err := rifle.base_file_decode(bytes)
	extra_require(t, header_err == nil)
	defer rifle.schema_destroy(header.schema)
	testing.expect(t, header.record_size == 8 && header.file_size == 8192)
	testing.expect(t, header.schema.record_size == 8 && len(header.schema.fields) == 1)
}

System_Writer :: struct {
	log:     ^rifle.Log,
	id:      int,
	barrier: ^sync.Barrier,
	err:     rifle.RifleError,
}

system_writer :: proc(t: ^thread.Thread) {
	w := cast(^System_Writer)t.data
	sync.barrier_wait(w.barrier)
	data: [7]i64
	for first := 0; first < 2048; {
		count := min(len(data), 2048 - first)
		for &v, i in data[:count] {v = i64(w.id * 2048 + first + i + 1)}
		bytes := (cast([^]u8)raw_data(data[:]))[:count * 8]
		_, w.err = rifle.log_write(w.log, bytes, i64(count))
		if w.err != nil {return}
		first += count
	}
}

@(test)
system_concurrent_log_cache_uring_writers :: proc(t: ^testing.T) {
	s := system_log_create(t)
	barrier: sync.Barrier
	sync.barrier_init(&barrier, 4)
	writers: [4]System_Writer
	threads: [4]^thread.Thread
	for &w, i in writers {
		w = {
			log     = s.log,
			id      = i,
			barrier = &barrier,
		}
		threads[i] = thread.create(system_writer)
		threads[i].data = &w
		thread.start(threads[i])
	}
	for worker in threads {
		thread.join(worker)
		thread.destroy(worker)
	}
	for w in writers {testing.expect(t, w.err == nil)}
	testing.expect_value(t, s.log.visible_index.value, i64(8192))
	system_drain_and_sync(t, s.log)
	seen: [8192]bool
	readback: [127]i64
	for first := 0; first < 8192; {
		count := min(len(readback), 8192 - first)
		bytes := (cast([^]u8)raw_data(readback[:]))[:count * 8]
		extra_require(t, rifle.log_read(s.log, bytes, i64(first), i64(count)) == nil)
		for v in readback[:count] {
			extra_require(t, v >= 1 && v <= 8192)
			extra_require(t, !seen[v - 1])
			seen[v - 1] = true
		}
		first += count
	}
}
