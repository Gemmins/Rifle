package test

import "core:fmt"
import "core:os"
import "core:testing"
import rifle "rifle:rifle"

// Use the cache poll/sync interface, as in the other system tests, until the
// separately tested public log_poll/log_sync forwarding bugs are fixed.
system_drop_wait :: proc(t: ^testing.T, s: ^System_Log, exclusive_file: i64) {
	pc := cast(^rifle.PageCache)s.log.cache.data
	for {
		_, err := s.log.cache.poll(s.log.cache.data)
		extra_require(t, err == nil)
		if pc.last_file_index == exclusive_file && !pc.unlink_pending {break}
	}
}

system_drop_append :: proc(t: ^testing.T, s: ^System_Log, start, count: i64) {
	data: [73]i64
	for first := start; first < start + count; {
		n := min(i64(len(data)), start + count - first)
		for &v, i in data[:n] {v = first + i64(i) + 1}
		bytes := (cast([^]u8)raw_data(data[:]))[:n * 8]
		index, err := rifle.log_write(s.log, bytes, n)
		extra_require(t, err == nil)
		testing.expect_value(t, index, first)
		first += n
	}
	system_drain_and_sync(t, s.log)
}

system_drop_check_files :: proc(t: ^testing.T, s: ^System_Log, first_file, end_file: i64) {
	for file in 0 ..< end_file {
		path := fmt.aprintf("%s/data_%d.rfl", s.path, file)
		defer delete(path)
		if file < first_file {
			testing.expect(t, !os.exists(path), path)
			continue
		}
		bytes, err := os.read_entire_file(path, context.allocator)
		extra_require(t, err == nil)
		defer delete(bytes)
		extra_require(t, len(bytes) == 8192)
		values := (cast([^]i64)raw_data(bytes))[:1024]
		for value, i in values {extra_require(t, value == file * 1024 + i64(i) + 1)}
	}
	base := fmt.aprintf("%s/base.rfl", s.path)
	defer delete(base)
	testing.expect(t, os.exists(base))
}

system_drop_check_reads :: proc(t: ^testing.T, s: ^System_Log, tail, head: i64) {
	data: [127]i64
	bytes := (cast([^]u8)raw_data(data[:]))[:size_of(data)]
	if tail > 0 {
		testing.expect(t, rifle.log_read(s.log, bytes[:8], tail - 1, 1) == .IndexOutOfBoundsError)
	}
	for first := tail; first < head; {
		n := min(i64(len(data)), head - first)
		extra_require(t, rifle.log_read(s.log, bytes[:n * 8], first, n) == nil)
		for value, i in data[:n] {extra_require(t, value == first + i64(i) + 1)}
		first += n
	}
}

@(test)
system_drop_file_boundaries_and_append :: proc(t: ^testing.T) {
	s := system_log_create(t)
	// Eight pages exceed the four-page cache, so retained reads include disk IO.
	system_drop_append(t, s, 0, 4096)
	system_drop_check_files(t, s, 0, 4)
	tails := []i64{1023, 1024, 2049, 4096}
	for tail in tails {
		extra_require(t, rifle.log_drop(s.log, tail) == nil)
		system_drop_wait(t, s, tail / 1024)
		system_drop_check_files(t, s, tail / 1024, 4)
		system_drop_check_reads(t, s, tail, 4096)
		testing.expect_value(t, s.log.trailing_index.value, tail)
		testing.expect_value(t, s.log.visible_index.value, i64(4096))
		testing.expect_value(t, s.log.durable_index.value, i64(4096))
		// Repeated, older, and out-of-range public drops must leave files intact.
		invalid_targets := []i64{tail, tail - 1, 4097}
		for invalid in invalid_targets {
			testing.expect(t, rifle.log_drop(s.log, invalid) == .IndexOutOfBoundsError)
		}
		system_drop_wait(t, s, tail / 1024)
		system_drop_check_files(t, s, tail / 1024, 4)
	}
	// Dropping everything must not prevent appending to the next file.
	system_drop_append(t, s, 4096, 1024)
	system_drop_check_files(t, s, 4, 5)
	system_drop_check_reads(t, s, 4096, 5120)
}

@(test)
system_drop_missing_file_and_extended_target :: proc(t: ^testing.T) {
	s := system_log_create(t)
	system_drop_append(t, s, 0, 4096)
	path := fmt.aprintf("%s/data_0.rfl", s.path)
	defer delete(path)
	extra_require(t, os.remove(path) == nil)
	extra_require(t, rifle.log_drop(s.log, 1024) == nil)
	_, err := s.log.cache.poll(s.log.cache.data)
	extra_require(t, err == nil)
	// Extend the target before waiting for the first deletion to settle. ENOENT
	// for file zero must not block the subsequent, real unlinks.
	extra_require(t, rifle.log_drop(s.log, 3072) == nil)
	system_drop_wait(t, s, 3)
	system_drop_check_files(t, s, 3, 4)
	system_drop_check_reads(t, s, 3072, 4096)
}
