
package test

import "core:mem"
import "core:os"
import "core:sys/linux"
import "core:sys/linux/uring"
import "core:testing"
import "core:time"
import rifle "rifle:rifle"

PAGE_SIZE :: 4096
BUFFER_SIZE :: 16 * PAGE_SIZE

Test_IO :: struct {
	io:            rifle.IO,
	buffer:        []u8,
	completions:   [128]rifle.IOCompletion,
	paths:         [8]string,
	path_count:    int,
	initialized:   bool,
	deinitialized: bool,
}

cleanup_test_io :: proc(ctx: rawptr) {
	s := cast(^Test_IO)ctx

	if s.io.data != nil {
		if s.initialized {
			_ = s.io.deinit(s.io.data)
		} else if !s.deinitialized {
			free(s.io.data)
		}
	}

	if s.buffer != nil {
		_ = mem.free_bytes(s.buffer)
	}

	for path in s.paths[:s.path_count] {
		_ = os.remove(path)
	}

	free(s)
}

new_test_io :: proc(t: ^testing.T) -> ^Test_IO {
	testing.set_fail_timeout(t, 10 * time.Second)

	s := new(Test_IO)
	testing.cleanup(t, cleanup_test_io, s)

	buffer, alloc_err := mem.alloc_bytes(BUFFER_SIZE, PAGE_SIZE)
	if !testing.expect(t, alloc_err == .None) {
		testing.fail_now(t)
	}
	s.buffer = buffer

	config := rifle.UringConfig{uring.DEFAULT_PARAMS, 128, 1 << 20}
	s.io = rifle.new_uring_io(config, linux.AT_FDCWD)

	if !testing.expect(t, s.io.data != nil) {
		testing.fail_now(t)
	}

	return s
}

setup_test_io :: proc(t: ^testing.T) -> ^Test_IO {
	s := new_test_io(t)

	err := s.io.init(s.io.data, s.buffer)
	if !testing.expect(t, err == nil) {
		testing.fail_now(t)
	}

	s.initialized = true
	return s
}

track_file :: proc(s: ^Test_IO, path: string) {
	assert(s.path_count < len(s.paths))
	s.paths[s.path_count] = path
	s.path_count += 1
	_ = os.remove(path)
}

poll_events :: proc(t: ^testing.T, s: ^Test_IO, expected: int) -> []rifle.IOCompletion {
	count := 0

	for count < expected {
		n, err := s.io.poll(s.io.data, s.completions[count:expected])

		if !testing.expect(t, err == nil) {
			testing.fail_now(t)
		}

		count += int(n)
	}

	return s.completions[:count]
}

expect_user_data :: proc(t: ^testing.T, events: []rifle.IOCompletion, expected: ..rifle.IOUserData) {
	testing.expect_value(t, len(events), len(expected))
	seen: [128]bool

	for event in events {
		found := false

		for data, i in expected {
			if event.user_data == data && !seen[i] {
				testing.expect(t, !seen[i])
				seen[i] = true
				found = true
				break
			}
		}

		testing.expect(t, found)
	}

	for i in 0 ..< len(expected) {
		testing.expect(t, seen[i])
	}
}

open_file :: proc(t: ^testing.T, s: ^Test_IO, file: rifle.RifleFile, page_index: u16) {
	data := rifle.IOUserData {
		op         = .OPEN,
		page_index = u32(page_index),
	}

	err := s.io.open(s.io.data, data, file)
	if !testing.expect(t, err == nil) {
		testing.fail_now(t)
	}

	events := poll_events(t, s, 1)
	testing.expect_value(t, events[0].user_data, data)
	testing.expect(t, events[0].res >= 0)
}

close_file :: proc(t: ^testing.T, s: ^Test_IO, file: rifle.RifleFile, page_index: u16) {
	// Test cleanup follows the same flush-before-close contract as callers.
	uio := cast(^rifle.UringIO)s.io.data
	dirty_count := 0
	for _, slot in uio.file_index.file_map {
		if uio.file_index.slots[slot].state == .Dirty {dirty_count += 1}
	}
	if dirty_count > 0 {
		extra_require(t, s.io.sync(s.io.data, {op = .SYNC}) == nil)
		for event in poll_events(t, s, 1) {
			extra_require(t, event.user_data.op == .SYNC && event.res == 0)
		}
	}
	data := rifle.IOUserData {
		op         = .CLOSE,
		page_index = u32(page_index),
	}

	err := s.io.close(s.io.data, data, file)
	if !testing.expect(t, err == nil) {
		testing.fail_now(t)
	}

	events := poll_events(t, s, 1)
	testing.expect_value(t, events[0].user_data, data)
	testing.expect(t, events[0].res >= 0)
}

@(test)
new_uring :: proc(t: ^testing.T) {
	config := rifle.UringConfig{uring.DEFAULT_PARAMS, 128, 1 << 20}

	io := rifle.new_uring_io(config, linux.AT_FDCWD)

	testing.expect(t, io.data != nil)

	free(io.data)
}

@(test)
uring_init :: proc(t: ^testing.T) {
	s := new_test_io(t)

	err := s.io.init(s.io.data, s.buffer)

	testing.expect(t, err == nil)
	s.initialized = err == nil
}

@(test)
uring_deinit :: proc(t: ^testing.T) {
	s := setup_test_io(t)

	err := s.io.deinit(s.io.data)
	s.initialized = false
	s.deinitialized = true

	testing.expect(t, err == nil)
}

@(test)
open_close_file :: proc(t: ^testing.T) {
	path :: "/tmp/rifle_test_open_close.rfl"
	s := setup_test_io(t)
	track_file(s, path)

	file := rifle.RifleFile{id = 100, path = path}
	data := rifle.IOUserData {
		page_index = 123,
		op         = .OPEN,
		payload    = 456,
	}

	err := s.io.open(s.io.data, data, file)
	testing.expect(t, err == nil)

	events := poll_events(t, s, 1)
	testing.expect_value(t, events[0].user_data, data)
	testing.expect(t, events[0].res >= 0)
	testing.expect(t, os.exists(path))

	data.op = .CLOSE

	err = s.io.close(s.io.data, data, file)
	testing.expect(t, err == nil)

	events = poll_events(t, s, 1)
	testing.expect_value(t, events[0].user_data, data)
	testing.expect(t, events[0].res >= 0)
}

@(test)
reopen_file :: proc(t: ^testing.T) {
	path :: "/tmp/rifle_test_reopen.rfl"
	s := setup_test_io(t)
	track_file(s, path)

	file := rifle.RifleFile{id = 100, path = path}

	open_file(t, s, file, 7)
	close_file(t, s, file, 7)

	testing.expect(t, os.exists(path))

	open_file(t, s, file, 7)
	close_file(t, s, file, 7)
}

@(test)
write_read_file :: proc(t: ^testing.T) {
	path :: "/tmp/rifle_test_write_read.rfl"
	s := setup_test_io(t)
	track_file(s, path)

	file := rifle.RifleFile{id = 100, path = path}
	open_file(t, s, file, 7)

	write_buffer := s.buffer[:PAGE_SIZE]
	read_buffer := s.buffer[PAGE_SIZE:2 * PAGE_SIZE]

	for i in 0 ..< PAGE_SIZE {
		write_buffer[i] = u8(i % 251)
	}

	data := rifle.IOUserData {
		page_index = 10,
		op         = .WRITE,
		payload    = 42,
	}

	err := s.io.write_at(s.io.data, data, write_buffer, 0, file)
	testing.expect(t, err == nil)

	events := poll_events(t, s, 1)
	testing.expect_value(t, events[0].user_data, data)
	testing.expect_value(t, events[0].res, i32(PAGE_SIZE))

	data.op = .READ
	data.payload = 43

	err = s.io.read_at(s.io.data, data, read_buffer, 0, file)
	testing.expect(t, err == nil)

	events = poll_events(t, s, 1)
	testing.expect_value(t, events[0].user_data, data)
	testing.expect_value(t, events[0].res, i32(PAGE_SIZE))

	for i in 0 ..< PAGE_SIZE {
		testing.expect_value(t, read_buffer[i], write_buffer[i])
	}

	close_file(t, s, file, 7)
}

@(test)
write_at_offsets :: proc(t: ^testing.T) {
	path :: "/tmp/rifle_test_offsets.rfl"
	s := setup_test_io(t)
	track_file(s, path)

	file := rifle.RifleFile{id = 100, path = path}
	open_file(t, s, file, 7)

	first := s.buffer[:PAGE_SIZE]
	second := s.buffer[PAGE_SIZE:2 * PAGE_SIZE]
	read_buffer := s.buffer[2 * PAGE_SIZE:3 * PAGE_SIZE]

	for i in 0 ..< PAGE_SIZE {
		first[i] = 17
		second[i] = 91
	}

	data_a := rifle.IOUserData {
		op         = .WRITE,
		page_index = 10,
		payload    = 1,
	}

	data_b := rifle.IOUserData {
		op         = .WRITE,
		page_index = 14,
		payload    = 2,
	}

	err := s.io.write_at(s.io.data, data_a, first, 0, file)
	testing.expect(t, err == nil)

	err = s.io.write_at(s.io.data, data_b, second, 4 * PAGE_SIZE, file)
	testing.expect(t, err == nil)

	events := poll_events(t, s, 2)
	expect_user_data(t, events, data_a, data_b)

	for event in events {
		testing.expect_value(t, event.res, i32(PAGE_SIZE))
	}

	read_data := rifle.IOUserData {
		op         = .READ,
		page_index = 14,
		payload    = 3,
	}

	err = s.io.read_at(s.io.data, read_data, read_buffer, 4 * PAGE_SIZE, file)
	testing.expect(t, err == nil)

	events = poll_events(t, s, 1)
	testing.expect_value(t, events[0].user_data, read_data)
	testing.expect_value(t, events[0].res, i32(PAGE_SIZE))

	for b in read_buffer {
		testing.expect_value(t, b, u8(91))
	}

	read_data.page_index = 10
	read_data.payload = 4

	err = s.io.read_at(s.io.data, read_data, read_buffer, 0, file)
	testing.expect(t, err == nil)

	events = poll_events(t, s, 1)
	testing.expect_value(t, events[0].user_data, read_data)
	testing.expect_value(t, events[0].res, i32(PAGE_SIZE))

	for b in read_buffer {
		testing.expect_value(t, b, u8(17))
	}

	close_file(t, s, file, 7)
}

@(test)
batched_writes :: proc(t: ^testing.T) {
	path :: "/tmp/rifle_test_batch.rfl"
	s := setup_test_io(t)
	track_file(s, path)

	file := rifle.RifleFile{id = 100, path = path}
	open_file(t, s, file, 7)

	expected: [8]rifle.IOUserData

	for i in 0 ..< 8 {
		buffer := s.buffer[i * PAGE_SIZE:(i + 1) * PAGE_SIZE]

		for j in 0 ..< PAGE_SIZE {
			buffer[j] = u8(i + 1)
		}

		data := rifle.IOUserData {
			op         = .WRITE,
			page_index = u32(i + 20),
			payload    = u32(i + 1),
		}

		expected[i] = data

		err := s.io.write_at(s.io.data, data, buffer, u64(i * PAGE_SIZE), file)
		testing.expect(t, err == nil)
	}

	events := poll_events(t, s, 8)
	seen: [8]bool

	for event in events {
		testing.expect_value(t, event.res, i32(PAGE_SIZE))

		found := false
		for data, i in expected {
			if event.user_data == data && !seen[i] {
				testing.expect(t, !seen[i])
				seen[i] = true
				found = true
				break
			}
		}

		testing.expect(t, found)
	}

	for found in seen {
		testing.expect(t, found)
	}

	close_file(t, s, file, 7)
}

@(test)
multiple_files :: proc(t: ^testing.T) {
	path_a :: "/tmp/rifle_test_file_a.rfl"
	path_b :: "/tmp/rifle_test_file_b.rfl"

	s := setup_test_io(t)
	track_file(s, path_a)
	track_file(s, path_b)

	file_a := rifle.RifleFile{id = 100, path = path_a}
	file_b := rifle.RifleFile{id = 200, path = path_b}

	data_a := rifle.IOUserData {
		op         = .OPEN,
		page_index = u32(7),
		payload    = 10,
	}

	data_b := rifle.IOUserData {
		op         = .OPEN,
		page_index = u32(12),
		payload    = 20,
	}

	err := s.io.open(s.io.data, data_a, file_a)
	testing.expect(t, err == nil)

	err = s.io.open(s.io.data, data_b, file_b)
	testing.expect(t, err == nil)

	events := poll_events(t, s, 2)
	expect_user_data(t, events, data_a, data_b)

	for event in events {
		testing.expect(t, event.res >= 0)
	}

	testing.expect(t, os.exists(path_a))
	testing.expect(t, os.exists(path_b))

	data_a.op = .CLOSE
	data_b.op = .CLOSE

	err = s.io.close(s.io.data, data_a, file_a)
	testing.expect(t, err == nil)

	err = s.io.close(s.io.data, data_b, file_b)
	testing.expect(t, err == nil)

	events = poll_events(t, s, 2)
	expect_user_data(t, events, data_a, data_b)

	for event in events {
		testing.expect(t, event.res >= 0)
	}
}

@(test)
open_delete_file :: proc(t: ^testing.T) {
	path :: "/tmp/rifle_test_open_delete.rfl"
	s := setup_test_io(t)
	track_file(s, path)

	file := rifle.RifleFile{id = 100, path = path}

	testing.expect(t, !os.exists(path))

	open_file(t, s, file, 7)
	testing.expect(t, os.exists(path))

	close_file(t, s, file, 7)

	data := rifle.IOUserData {
		op      = .DELETE,
		payload = 123,
	}

	err := s.io.unlink(s.io.data, data, file)
	testing.expect(t, err == nil)

	events := poll_events(t, s, 1)
	testing.expect_value(t, events[0].user_data, data)
	testing.expect(t, events[0].res >= 0)
	testing.expect(t, !os.exists(path))
}
extra_require :: proc(t: ^testing.T, ok: bool) {
	if !testing.expect(t, ok) {
		testing.fail_now(t)
	}
}

extra_pattern :: proc(buffer: []u8, seed: int) {
	for i in 0 ..< len(buffer) {
		buffer[i] = u8((i * 17 + seed * 31) % 251)
	}
}

extra_expect_pattern :: proc(t: ^testing.T, buffer: []u8, seed: int) {
	for b, i in buffer {
		if !testing.expect(t, b == u8((i * 17 + seed * 31) % 251)) {
			testing.fail_now(t)
		}
	}
}

// Always offer the entire array, so this helper doesn't accidentally depend
// on support for small output slices. The dedicated small-slice test does.
// Existing setup sets a 10-second testing timeout for missing completions.
extra_collect :: proc(t: ^testing.T, s: ^Test_IO, expected: []rifle.IOUserData, results: []i32) {
	assert(len(expected) == len(results))
	assert(len(expected) <= 128)
	seen: [128]bool
	count := 0
	for count < len(expected) {
		n, err := s.io.poll(s.io.data, s.completions[:])
		extra_require(t, err == nil)
		extra_require(t, int(n) <= len(s.completions))
		for event in s.completions[:int(n)] {
			found := false
			for data, i in expected {
				if event.user_data == data && !seen[i] {
					extra_require(t, !seen[i])
					extra_require(t, event.res == results[i])
					seen[i] = true
					found = true
					count += 1
					break
				}
			}
			extra_require(t, found)
		}
	}
}

extra_one :: proc(t: ^testing.T, s: ^Test_IO, data: rifle.IOUserData, result: i32) {
	expected := [1]rifle.IOUserData{data}
	results := [1]i32{result}
	extra_collect(t, s, expected[:], results[:])
}

extra_write :: proc(t: ^testing.T, s: ^Test_IO, file: rifle.RifleFile, index: u16, buffer: []u8, offset: u64) {
	data := rifle.IOUserData {
		op         = .WRITE,
		page_index = u32(index),
		payload    = 101,
	}
	extra_require(t, s.io.write_at(s.io.data, data, buffer, offset, file) == nil)
	extra_one(t, s, data, i32(len(buffer)))
}

extra_read :: proc(t: ^testing.T, s: ^Test_IO, file: rifle.RifleFile, index: u16, buffer: []u8, offset: u64, seed: int) {
	// Poison the destination so a no-op read cannot pass from stale contents.
	for &b in buffer {b = 255}
	data := rifle.IOUserData {
		op         = .READ,
		page_index = u32(index),
		payload    = 102,
	}
	extra_require(t, s.io.read_at(s.io.data, data, buffer, offset, file) == nil)
	extra_one(t, s, data, i32(len(buffer)))
	extra_expect_pattern(t, buffer, seed)
}

@(test)
uring_extra_idle_poll :: proc(t: ^testing.T) {
	s := setup_test_io(t)
	for _ in 0 ..< 32 {
		n, err := s.io.poll(s.io.data, s.completions[:])
		extra_require(t, err == nil)
		testing.expect_value(t, n, u32(0))
	}
}

@(test)
uring_extra_reopen_preserves_data :: proc(t: ^testing.T) {
	s := setup_test_io(t)
	path :: "/tmp/rifle_extra_reopen.rfl"
	track_file(s, path)
	file := rifle.RifleFile{id = 301, path = path}
	open_file(t, s, file, 7)
	extra_pattern(s.buffer[:PAGE_SIZE], 11)
	extra_write(t, s, file, 7, s.buffer[:PAGE_SIZE], 3 * PAGE_SIZE)
	close_file(t, s, file, 7)
	open_file(t, s, file, 9)
	extra_read(t, s, file, 9, s.buffer[PAGE_SIZE:2 * PAGE_SIZE], 3 * PAGE_SIZE, 11)
	close_file(t, s, file, 9)
}

@(test)
uring_extra_last_registered_page_and_file_page :: proc(t: ^testing.T) {
	s := setup_test_io(t)
	path :: "/tmp/rifle_extra_last_page.rfl"
	track_file(s, path)
	file := rifle.RifleFile{id = 302, path = path}
	open_file(t, s, file, 7)
	last := s.buffer[BUFFER_SIZE - PAGE_SIZE:]
	extra_pattern(last, 12)
	// Default fixture preallocates 1 MiB. Exercise its final full page.
	offset: u64 = (1 << 20) - PAGE_SIZE
	extra_write(t, s, file, 7, last, offset)
	extra_read(t, s, file, 7, last, offset, 12)
	close_file(t, s, file, 7)
}

@(test)
uring_extra_multi_page_transfer :: proc(t: ^testing.T) {
	s := setup_test_io(t)
	path :: "/tmp/rifle_extra_multi_page.rfl"
	track_file(s, path)
	file := rifle.RifleFile{id = 303, path = path}
	open_file(t, s, file, 7)
	source := s.buffer[:3 * PAGE_SIZE]
	destination := s.buffer[5 * PAGE_SIZE:8 * PAGE_SIZE]
	extra_pattern(source, 13)
	extra_write(t, s, file, 7, source, 7 * PAGE_SIZE)
	extra_read(t, s, file, 7, destination, 7 * PAGE_SIZE, 13)
	close_file(t, s, file, 7)
}

@(test)
uring_extra_overwrite_preserves_neighbours :: proc(t: ^testing.T) {
	s := setup_test_io(t)
	path :: "/tmp/rifle_extra_overwrite.rfl"
	track_file(s, path)
	file := rifle.RifleFile{id = 304, path = path}
	open_file(t, s, file, 7)
	for i in 0 ..< 3 {
		extra_pattern(s.buffer[:PAGE_SIZE], i + 1)
		extra_write(t, s, file, 7, s.buffer[:PAGE_SIZE], u64(i * PAGE_SIZE))
	}
	extra_pattern(s.buffer[:PAGE_SIZE], 99)
	extra_write(t, s, file, 7, s.buffer[:PAGE_SIZE], PAGE_SIZE)
	for i in 0 ..< 3 {
		seed := i + 1
		if i == 1 {seed = 99}
		extra_read(t, s, file, 7, s.buffer[PAGE_SIZE:2 * PAGE_SIZE], u64(i * PAGE_SIZE), seed)
	}
	close_file(t, s, file, 7)
}

@(test)
uring_extra_batched_reads :: proc(t: ^testing.T) {
	s := setup_test_io(t)
	path :: "/tmp/rifle_extra_batched_reads.rfl"
	track_file(s, path)
	file := rifle.RifleFile{id = 305, path = path}
	open_file(t, s, file, 7)
	for i in 0 ..< 8 {
		extra_pattern(s.buffer[:PAGE_SIZE], i + 20)
		extra_write(t, s, file, 7, s.buffer[:PAGE_SIZE], u64(i * PAGE_SIZE))
	}
	expected: [8]rifle.IOUserData
	results: [8]i32
	for i in 0 ..< 8 {
		// Reverse disk order and use separate registered destinations.
		expected[i] = rifle.IOUserData {
			op         = .READ,
			page_index = u32(7 - i),
			payload    = u32(200 + i),
		}
		results[i] = PAGE_SIZE
		dst := s.buffer[i * PAGE_SIZE:(i + 1) * PAGE_SIZE]
		for &b in dst {b = 255}
		extra_require(t, s.io.read_at(s.io.data, expected[i], dst, u64((7 - i) * PAGE_SIZE), file) == nil)
	}
	extra_collect(t, s, expected[:], results[:])
	for i in 0 ..< 8 {
		extra_expect_pattern(t, s.buffer[i * PAGE_SIZE:(i + 1) * PAGE_SIZE], 27 - i)
	}
	close_file(t, s, file, 7)
}

@(test)
uring_extra_file_isolation :: proc(t: ^testing.T) {
	s := setup_test_io(t)
	paths := [2]cstring{"/tmp/rifle_extra_isolation_a.rfl", "/tmp/rifle_extra_isolation_b.rfl"}
	files := [2]rifle.RifleFile{{id = 306, path = paths[0]}, {id = 900001, path = paths[1]}}
	indices := [2]u16{7, 42}
	expected: [2]rifle.IOUserData
	results := [2]i32{PAGE_SIZE, PAGE_SIZE}
	for i in 0 ..< 2 {
		track_file(s, string(paths[i]))
		open_file(t, s, files[i], indices[i])
	}
	for i in 0 ..< 2 {
		src := s.buffer[i * PAGE_SIZE:(i + 1) * PAGE_SIZE]
		extra_pattern(src, i + 30)
		expected[i] = rifle.IOUserData {
			op         = .WRITE,
			page_index = u32(indices[i]),
			payload    = u32(300 + i),
		}
		extra_require(t, s.io.write_at(s.io.data, expected[i], src, 2 * PAGE_SIZE, files[i]) == nil)
	}
	extra_collect(t, s, expected[:], results[:])
	for i in 0 ..< 2 {
		extra_read(t, s, files[i], indices[i], s.buffer[2 * PAGE_SIZE:3 * PAGE_SIZE], 2 * PAGE_SIZE, i + 30)
		close_file(t, s, files[i], indices[i])
	}
}

@(test)
uring_extra_slot_reuse :: proc(t: ^testing.T) {
	s := new_test_io(t)
	uio := cast(^rifle.UringIO)s.io.data
	uio.config.num_files = 2
	err := s.io.init(s.io.data, s.buffer)
	s.initialized = err == nil
	extra_require(t, err == nil)
	paths := [2]cstring{"/tmp/rifle_extra_reuse_a.rfl", "/tmp/rifle_extra_reuse_b.rfl"}
	for path in paths {track_file(s, string(path))}
	// More distinct file identities than available slots; page indices stay
	// within capacity, but change as a registered slot is recycled.
	for round in 0 ..< 8 {
		file := rifle.RifleFile{id = i64(400 + round), path = paths[round % 2]}
		index := u16(round % 2)
		open_file(t, s, file, index)
		extra_pattern(s.buffer[:PAGE_SIZE], round + 40)
		extra_write(t, s, file, index, s.buffer[:PAGE_SIZE], 0)
		extra_read(t, s, file, index, s.buffer[PAGE_SIZE:2 * PAGE_SIZE], 0, round + 40)
		close_file(t, s, file, index)
	}
}

@(test)
uring_extra_one_completion_at_a_time :: proc(t: ^testing.T) {
	s := setup_test_io(t)
	path :: "/tmp/rifle_extra_small_poll.rfl"
	track_file(s, path)
	file := rifle.RifleFile{id = 307, path = path}
	open_file(t, s, file, 7)
	expected: [8]rifle.IOUserData
	for i in 0 ..< 8 {
		src := s.buffer[i * PAGE_SIZE:(i + 1) * PAGE_SIZE]
		extra_pattern(src, i + 50)
		expected[i] = rifle.IOUserData {
			op         = .WRITE,
			page_index = u32(7),
			payload    = u32(500 + i),
		}
		extra_require(t, s.io.write_at(s.io.data, expected[i], src, u64(i * PAGE_SIZE), file) == nil)
	}
	seen: [8]bool
	count := 0
	for count < 8 {
		n, err := s.io.poll(s.io.data, s.completions[:1])
		extra_require(t, err == nil)
		extra_require(t, n <= 1)
		if n == 0 {continue}
		event := s.completions[0]
		extra_require(t, event.res == PAGE_SIZE)
		found := false
		for data, i in expected {
			if event.user_data == data && !seen[i] {
				extra_require(t, !seen[i])
				seen[i] = true
				found = true
				break
			}
		}
		extra_require(t, found)
		count += 1
	}
	close_file(t, s, file, 7)
}

@(test)
uring_extra_sync_before_write_reap :: proc(t: ^testing.T) {
	s := setup_test_io(t)
	path :: "/tmp/rifle_extra_sync_pending.rfl"
	track_file(s, path)
	file := rifle.RifleFile{id = 308, path = path}
	open_file(t, s, file, 7)
	extra_pattern(s.buffer[:PAGE_SIZE], 60)
	write_data := rifle.IOUserData {
		op         = .WRITE,
		page_index = u32(7),
		payload    = 600,
	}
	sync_data := rifle.IOUserData {
		op         = .SYNC,
		page_index = u32(7),
		payload    = 601,
	}
	extra_require(t, s.io.write_at(s.io.data, write_data, s.buffer[:PAGE_SIZE], 0, file) == nil)
	extra_require(t, s.io.sync(s.io.data, sync_data) == nil)
	// Assert write-before-sync delivery even across different poll calls.
	write_seen, sync_seen := false, false
	for !sync_seen {
		n, err := s.io.poll(s.io.data, s.completions[:])
		extra_require(t, err == nil)
		for event in s.completions[:int(n)] {
			if event.user_data == write_data {
				extra_require(t, !write_seen)
				extra_require(t, event.res == PAGE_SIZE)
				write_seen = true
			} else if event.user_data == sync_data {
				extra_require(t, write_seen && !sync_seen)
				extra_require(t, event.res == 0)
				sync_seen = true
			} else {
				extra_require(t, false)
			}
		}
	}
	extra_read(t, s, file, 7, s.buffer[PAGE_SIZE:2 * PAGE_SIZE], 0, 60)
	close_file(t, s, file, 7)
}

@(test)
uring_extra_sync_multiple_dirty_files :: proc(t: ^testing.T) {
	s := setup_test_io(t)
	paths := [2]cstring{"/tmp/rifle_extra_sync_a.rfl", "/tmp/rifle_extra_sync_b.rfl"}
	files := [2]rifle.RifleFile{{id = 309, path = paths[0]}, {id = 310, path = paths[1]}}
	indices := [2]u16{7, 42}
	for i in 0 ..< 2 {
		track_file(s, string(paths[i]))
		open_file(t, s, files[i], indices[i])
	}
	// Two generations: a later write must make each file eligible again.
	for generation in 0 ..< 2 {
		for i in 0 ..< 2 {
			extra_pattern(s.buffer[:PAGE_SIZE], 70 + generation * 2 + i)
			extra_write(t, s, files[i], indices[i], s.buffer[:PAGE_SIZE], u64(generation * PAGE_SIZE))
		}
		data := rifle.IOUserData {
			op         = .SYNC,
			page_index = 123,
			payload    = u32(700 + generation),
		}
		extra_require(t, s.io.sync(s.io.data, data) == nil)
		extra_one(t, s, data, 0)
	}
	for i in 0 ..< 2 {close_file(t, s, files[i], indices[i])}
}

@(test)
uring_extra_delete_preserves_request_token :: proc(t: ^testing.T) {
	s := setup_test_io(t)
	path :: "/tmp/rifle_extra_delete_token.rfl"
	track_file(s, path)
	file := rifle.RifleFile{id = 311, path = path}
	open_file(t, s, file, 7)
	close_file(t, s, file, 7)
	// DELETE uses a path, not a registered slot. Its token is opaque.
	data := rifle.IOUserData {
		op         = .DELETE,
		page_index = 0xffffff,
		payload    = 0xffffff,
	}
	extra_require(t, s.io.unlink(s.io.data, data, file) == nil)
	extra_one(t, s, data, 0)
	testing.expect(t, !os.exists(path))
}
