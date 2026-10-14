package test

import "core:os"
import "core:sys/linux"
import "core:sys/linux/uring"
import "core:testing"
import rifle "rifle:rifle"

// Supply real CQE layouts without kernel I/O so failure and trailing-timeout
// ordering are deterministic. SQ head/tail stay equal, so poll never submits.
Close_Test_IO :: struct {
	io:         rifle.UringIO,
	sq_head:    u32,
	cq_head:    u32,
	cq_tail:    u32,
	cqes:       [2]linux.IO_Uring_CQE,
	slots:      [2]rifle.FileSlot,
	free_slots: [2]u16,
}

cleanup_close_test_io :: proc(ctx: rawptr) {
	s := cast(^Close_Test_IO)ctx
	delete(s.io.file_index.file_map)
	free(s)
}

make_close_test_io :: proc(t: ^testing.T, close_result: i32) -> ^Close_Test_IO {
	s := new(Close_Test_IO)
	testing.cleanup(t, cleanup_close_test_io, s)
	s.slots[1] = {file_id = 901, state = .Closing, cache_index = 7}
	s.io.file_index = rifle.FileIndex {
		slots      = s.slots[:],
		file_map   = make(map[i64]u16),
		slot_stack = {top = 1, data = s.free_slots[:]},
	}
	s.io.file_index.file_map[901] = 1
	s.io.ring.sq.head = &s.sq_head
	s.cq_tail = 2
	s.io.ring.cq = uring.Completion_Queue {
		head = &s.cq_head,
		tail = &s.cq_tail,
		mask = 1,
		cqes = s.cqes[:],
	}
	ud := rifle.UringUserData {
		page_index = 123,
		file_index = 1,
		op         = .CLOSE,
		payload    = 456,
	}
	s.cqes[0] = {user_data = cast(u64)ud, res = close_result}
	ud.op = .TIMEOUT
	s.cqes[1] = {user_data = cast(u64)ud, res = -i32(linux.Errno.ECANCELED)}
	return s
}

@(test)
uring_close_failure_keeps_slot :: proc(t: ^testing.T) {
	s := make_close_test_io(t, -i32(linux.Errno.EIO))
	completions: [1]rifle.IOCompletion
	n, err := rifle.uring_poll(&s.io, completions[:])
	extra_require(t, err == nil && n == 1)
	testing.expect_value(t, completions[0].res, -i32(linux.Errno.EIO))
	testing.expect_value(t, completions[0].user_data, rifle.IOUserData {
		page_index = 123,
		file_index = 7,
		op         = .CLOSE,
		payload    = 456,
	})
	slot, exists := s.io.file_index.file_map[901]
	testing.expect(t, exists && slot == 1)
	testing.expect(t, s.slots[1].file_id == 901 && s.slots[1].cache_index == 7)
	testing.expect(t, s.slots[1].state == .Closing)
	testing.expect(t, s.io.file_index.slot_stack.top == 1)
	testing.expect(t, s.cq_head == 1)
}

@(test)
uring_close_fits_two_remaining_sqes :: proc(t: ^testing.T) {
	s := make_close_test_io(t, 0)
	s.slots[1].state = .Open
	sqes: [4]linux.IO_Uring_SQE
	s.io.ring.sq.sqes = sqes[:]
	s.io.ring.sq.mask = 3
	s.io.ring.sq.sqe_tail = 2
	data := rifle.IOUserData{op = .CLOSE, file_index = 7}
	extra_require(t, rifle.uring_close(&s.io, data, {901, nil}) == nil)
	testing.expect(t, s.io.ring.sq.sqe_tail == 4)
	testing.expect(t, sqes[2].opcode == .CLOSE && sqes[3].opcode == .LINK_TIMEOUT)
	testing.expect(t, sqes[2].file_index == 2)
	testing.expect(t, s.slots[1].state == .Closing)
	// Ownership is still reserved until the close completes.
	testing.expect(t, s.io.file_index.slot_stack.top == 1)
}

@(test)
uring_open_chains_reject_without_claiming_slot :: proc(t: ^testing.T) {
	// Cover insufficient space, including a completely full SQ.
	for pending in u32(1) ..< 5 {
		s := make_close_test_io(t, 0)
		sqes: [4]linux.IO_Uring_SQE
		s.io.ring.sq.sqes = sqes[:]
		s.io.ring.sq.mask = 3
		s.io.ring.sq.sqe_tail = pending
		file := rifle.RifleFile{902, nil}
		buffer: [PAGE_SIZE]u8
		if pending >= 2 {
			testing.expect(t, rifle.uring_open(&s.io, {op = .OPEN}, file) == .GenericError)
		}
		testing.expect(t, rifle.uring_readat(&s.io, {op = .READ}, buffer[:], 0, file) == .GenericError)
		testing.expect(t, rifle.uring_writeat(&s.io, {op = .WRITE}, buffer[:], 0, file) == .GenericError)
		testing.expect(t, s.io.ring.sq.sqe_tail == pending)
		testing.expect(t, s.io.file_index.slot_stack.top == 1)
		testing.expect(t, len(s.io.file_index.file_map) == 1)
		_, exists := s.io.file_index.file_map[file.id]
		testing.expect(t, !exists)
		testing.expect(t, s.slots[0].state == .Empty)
	}
}

@(test)
uring_open_chains_fit_exact_remaining_space :: proc(t: ^testing.T) {
	operations := [3]rifle.IOOperation{.OPEN, .READ, .WRITE}
	for operation in operations {
		s := make_close_test_io(t, 0)
		sqes: [4]linux.IO_Uring_SQE
		s.io.ring.sq.sqes = sqes[:]
		s.io.ring.sq.mask = 3
		s.io.ring.sq.sqe_tail = operation == .OPEN ? 1 : 0
		file := rifle.RifleFile{902, nil}
		buffer: [PAGE_SIZE]u8
		data := rifle.IOUserData{op = operation, file_index = 42}
		if operation == .OPEN {
			extra_require(t, rifle.uring_open(&s.io, data, file) == nil)
			testing.expect(t, sqes[2].opcode == .FALLOCATE)
		} else if operation == .READ {
			extra_require(t, rifle.uring_readat(&s.io, data, buffer[:], 0, file) == nil)
			testing.expect(t, sqes[2].opcode == .READ_FIXED)
		} else {
			extra_require(t, rifle.uring_writeat(&s.io, data, buffer[:], 0, file) == nil)
			testing.expect(t, sqes[2].opcode == .WRITE_FIXED)
		}
		testing.expect(t, s.io.ring.sq.sqe_tail == 4)
		open_index := operation == .OPEN ? 1 : 0
		testing.expect(t, sqes[open_index].opcode == .OPENAT && sqes[open_index].file_index == 1)
		testing.expect(t, sqes[open_index + 1].opcode == .FALLOCATE)
		testing.expect(t, s.slots[0].state == (operation == .WRITE ? .Dirty : .Opening))
		if operation != .READ {
			testing.expect(t, sqes[open_index].len == 0o666)
		}
		testing.expect(t, sqes[3].opcode == .LINK_TIMEOUT)
		slot, exists := s.io.file_index.file_map[file.id]
		testing.expect(t, exists && slot == 0)
		testing.expect(t, s.slots[0].file_id == file.id && s.slots[0].cache_index == 42)
	}
}

@(test)
uring_close_late_timeout_preserves_reused_slot :: proc(t: ^testing.T) {
	s := make_close_test_io(t, 0)
	completions: [1]rifle.IOCompletion
	n, err := rifle.uring_poll(&s.io, completions[:])
	extra_require(t, err == nil && n == 1)
	testing.expect(t, completions[0].res == 0 && completions[0].user_data.file_index == 7)
	_, exists := s.io.file_index.file_map[901]
	testing.expect(t, !exists)
	testing.expect(t, s.slots[1].file_id == 0 && s.slots[1].cache_index == 0)
	testing.expect(t, s.slots[1].state == .Empty)
	testing.expect(t, s.io.file_index.slot_stack.top == 2)
	testing.expect(t, s.cq_head == 1)

	// Reuse immediately, leaving the old close's timeout CQE unread.
	slot, registered := rifle.register_file(&s.io.file_index, {902, nil}, 0xfff)
	extra_require(t, registered && slot == 1)
	s.slots[slot].state = .Open
	n, err = rifle.uring_poll(&s.io, completions[:])
	testing.expect(t, err == nil && n == 0)
	testing.expect(t, s.cq_head == 2)
	testing.expect(t, s.slots[slot].file_id == 902 && s.slots[slot].cache_index == 0xfff)
	testing.expect(t, s.slots[slot].state == .Open)
	testing.expect(t, s.io.file_index.slot_stack.top == 1)
	mapped, present := s.io.file_index.file_map[902]
	testing.expect(t, present && mapped == slot)
	// No ready CQEs means a subsequent poll cannot recycle the slot again.
	n, err = rifle.uring_poll(&s.io, completions[:])
	testing.expect(t, err == nil && n == 0)
	testing.expect(t, s.io.file_index.slot_stack.top == 1)
}

@(test)
uring_close_after_sync_returns_capacity :: proc(t: ^testing.T) {
	s := new_test_io(t)
	uio := cast(^rifle.UringIO)s.io.data
	uio.config.num_files = 1
	err := s.io.init(s.io.data, s.buffer)
	s.initialized = err == nil
	extra_require(t, err == nil)
	path :: "/tmp/rifle_close_pending_write.rfl"
	track_file(s, path)
	file := rifle.RifleFile{903, path}
	open_file(t, s, file, 7)
	// Duplicate and exhausted registration must not change slot ownership.
	open_data := rifle.IOUserData{op = .OPEN, file_index = 42}
	testing.expect(t, s.io.open(s.io.data, open_data, file) != nil)
	testing.expect(t, s.io.open(s.io.data, open_data, {904, path}) != nil)
	testing.expect(t, len(uio.file_index.file_map) == 1 && uio.file_index.slots[0].file_id == file.id)

	extra_pattern(s.buffer[:PAGE_SIZE], 91)
	write_data := rifle.IOUserData{op = .WRITE, file_index = 7, payload = 101}
	extra_require(t, s.io.write_at(s.io.data, write_data, s.buffer[:PAGE_SIZE], 0, file) == nil)
	extra_one(t, s, write_data, PAGE_SIZE)
	extra_require(t, s.io.sync(s.io.data, {op = .SYNC, file_index = 7}) == nil)
	testing.expect(t, uio.file_index.slots[0].state == .Flushing)
	extra_one(t, s, {op = .SYNC, file_index = 7}, 0)
	testing.expect(t, uio.file_index.slots[0].state == .Open)
	close_file(t, s, file, 7)
	testing.expect(t, len(uio.file_index.file_map) == 0)
	testing.expect(t, uio.file_index.slot_stack.top == 1)
	// The same registered slot can now serve a new identity and cache index.
	new_file := rifle.RifleFile{904, path}
	open_file(t, s, new_file, 0xfff)
	extra_read(t, s, new_file, 0xfff, s.buffer[PAGE_SIZE:2 * PAGE_SIZE], 0, 91)
	close_file(t, s, new_file, 0xfff)
}

@(test)
uring_implicit_read_uses_registered_slots :: proc(t: ^testing.T) {
	s := new_test_io(t)
	uio := cast(^rifle.UringIO)s.io.data
	uio.config.num_files = 2
	err := s.io.init(s.io.data, s.buffer)
	s.initialized = err == nil
	extra_require(t, err == nil)
	paths := [2]cstring{"/tmp/rifle_implicit_read_a.rfl", "/tmp/rifle_implicit_read_b.rfl"}
	indices := [2]u16{7, 42}
	files := [2]rifle.RifleFile{{905, paths[0]}, {906, paths[1]}}
	for path, i in paths {
		track_file(s, string(path))
		src := s.buffer[i * PAGE_SIZE:(i + 1) * PAGE_SIZE]
		extra_pattern(src, 92 + i)
		extra_require(t, os.write_entire_file(string(path), src) == nil)
	}
	// Keep both files registered: the first implicit open claims slot 1,
	// and the second claims slot 0. No explicit open precedes either read.
	for file, i in files {
		dst := s.buffer[(i + 2) * PAGE_SIZE:(i + 3) * PAGE_SIZE]
		data := rifle.IOUserData{op = .READ, file_index = indices[i], payload = 102}
		extra_require(t, s.io.read_at(s.io.data, data, dst, 0, file) == nil)
		opened := data
		opened.op = .OPEN
		expected := [2]rifle.IOUserData{opened, data}
		results := [2]i32{0, PAGE_SIZE}
		extra_collect(t, s, expected[:], results[:])
		extra_expect_pattern(t, dst, 92 + i)
		slot, exists := uio.file_index.file_map[file.id]
		extra_require(t, exists && slot == u16(1 - i))
	}
	// Opening the second file must not replace the first file's descriptor.
	for file, i in files {
		extra_read(t, s, file, indices[i], s.buffer[(i + 2) * PAGE_SIZE:(i + 3) * PAGE_SIZE], 0, 92 + i)
		close_file(t, s, file, indices[i])
	}
}

@(test)
uring_implicit_write_uses_registered_slots :: proc(t: ^testing.T) {
	s := new_test_io(t)
	uio := cast(^rifle.UringIO)s.io.data
	uio.config.num_files = 2
	err := s.io.init(s.io.data, s.buffer)
	s.initialized = err == nil
	extra_require(t, err == nil)
	paths := [2]cstring{"/tmp/rifle_implicit_write_a.rfl", "/tmp/rifle_implicit_write_b.rfl"}
	indices := [2]u16{7, 42}
	files := [2]rifle.RifleFile{{907, paths[0]}, {908, paths[1]}}
	// Both writes create and open their files implicitly, using slots 1 and 0.
	for file, i in files {
		track_file(s, string(paths[i]))
		src := s.buffer[i * PAGE_SIZE:(i + 1) * PAGE_SIZE]
		extra_pattern(src, 94 + i)
		data := rifle.IOUserData{op = .WRITE, file_index = indices[i], payload = 101}
		extra_require(t, s.io.write_at(s.io.data, data, src, 0, file) == nil)
		opened := data
		opened.op = .OPEN
		expected := [2]rifle.IOUserData{opened, data}
		results := [2]i32{0, PAGE_SIZE}
		extra_collect(t, s, expected[:], results[:])
		slot, exists := uio.file_index.file_map[file.id]
		extra_require(t, exists && slot == u16(1 - i))
	}
	for file, i in files {
		extra_read(t, s, file, indices[i], s.buffer[(i + 2) * PAGE_SIZE:(i + 3) * PAGE_SIZE], 0, 94 + i)
		close_file(t, s, file, indices[i])
	}
}

@(test)
uring_implicit_allocation_transitions :: proc(t: ^testing.T) {
	dirty_values := [2]bool{false, true}
	for dirty in dirty_values {
		s := make_close_test_io(t, 0)
		s.slots[1].state = dirty ? .Dirty : .Opening
		s.cq_tail = 1
		ud := rifle.UringUserData{op = .ALLOCATE, file_index = 1}
		s.cqes[0] = {user_data = cast(u64)ud, res = 0}
		completions: [1]rifle.IOCompletion
		n, err := rifle.uring_poll(&s.io, completions[:])
		testing.expect(t, err == nil && n == 1)
		testing.expect(t, completions[0].user_data.op == .OPEN && completions[0].user_data.file_index == 7)
		testing.expect(t, s.slots[1].state == (dirty ? .Dirty : .Open))
		ud.op = dirty ? .WRITE : .READ
		s.cqes[1] = {user_data = cast(u64)ud, res = PAGE_SIZE}
		s.cq_tail = 2
		n, err = rifle.uring_poll(&s.io, completions[:])
		testing.expect(t, err == nil && n == 1)
		testing.expect(t, s.slots[1].state == (dirty ? .Dirty : .Open))
	}
}

@(test)
uring_sync_reserves_whole_batch :: proc(t: ^testing.T) {
	s := make_close_test_io(t, 0)
	s.slots[1].state = .Dirty
	slot, ok := rifle.register_file(&s.io.file_index, {902, nil}, 42)
	extra_require(t, ok)
	s.slots[slot].state = .Dirty
	sqes: [4]linux.IO_Uring_SQE
	s.io.ring.sq.sqes = sqes[:]
	s.io.ring.sq.mask = 3
	s.io.ring.sq.sqe_tail = 1
	testing.expect(t, rifle.uring_sync(&s.io, {}) == .GenericError)
	testing.expect(t, s.io.ring.sq.sqe_tail == 1 && s.io.pending_syncs == 0)
	testing.expect(t, s.slots[0].state == .Dirty && s.slots[1].state == .Dirty)
	s.io.ring.sq.sqe_tail = 0
	extra_require(t, rifle.uring_sync(&s.io, {}) == nil)
	testing.expect(t, s.io.ring.sq.sqe_tail == 4 && s.io.pending_syncs == 2)
	testing.expect(t, s.slots[0].state == .Flushing && s.slots[1].state == .Flushing)
}

@(test)
uring_sync_completion_preserves_new_writes :: proc(t: ^testing.T) {
	for scenario in 0 ..< 3 {
		s := make_close_test_io(t, 0)
		s.slots[1].state = .Dirty
		sqes: [4]linux.IO_Uring_SQE
		s.io.ring.sq.sqes = sqes[:]
		s.io.ring.sq.mask = 3
		extra_require(t, rifle.uring_sync(&s.io, {}) == nil)
		testing.expect(t, s.slots[1].state == .Flushing)
		if scenario == 2 {
			buffer: [PAGE_SIZE]u8
			extra_require(t, rifle.uring_writeat(&s.io, {}, buffer[:], 0, {901, nil}) == nil)
		}
		// Simulate consumption and completion without submitting to the kernel.
		s.sq_head = s.io.ring.sq.sqe_tail
		s.cq_tail = 1
		ud := rifle.UringUserData{op = .SYNC, file_index = 1}
		s.cqes[0] = {
			user_data = cast(u64)ud,
			res = scenario == 1 ? -i32(linux.Errno.EIO) : 0,
		}
		completions: [1]rifle.IOCompletion
		n, err := rifle.uring_poll(&s.io, completions[:])
		testing.expect(t, err == nil && n == 1 && s.io.pending_syncs == 0)
		testing.expect(t, s.slots[1].state == (scenario == 0 ? .Open : .Dirty))
	}
}
