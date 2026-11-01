package test

import "core:sys/linux"
import "core:testing"
import rifle "rifle:rifle"

@(test)
uring_existing_file_rejects_insufficient_queue_space :: proc(t: ^testing.T) {
	for pending in u32(3) ..= 4 {
		s := make_close_test_io(t, 0)
		s.slots[1].state = .Open
		sqes: [4]linux.IO_Uring_SQE
		s.io.ring.sq.sqes = sqes[:]
		s.io.ring.sq.mask = 3
		s.io.ring.sq.sqe_tail = pending
		buffer: [PAGE_SIZE]u8
		file := rifle.RifleFile{id = 901}
		testing.expect(t, rifle.uring_readat(&s.io, {}, buffer[:], 0, file) != nil)
		testing.expect(t, rifle.uring_writeat(&s.io, {}, buffer[:], 0, file) != nil)
		testing.expect_value(t, s.io.ring.sq.sqe_tail, pending)
		testing.expect(t, s.slots[1].state == .Open)
	}
}

@(test)
uring_transfer_results_and_tokens_survive_polling :: proc(t: ^testing.T) {
	ops := []rifle.UringOp{.READ, .WRITE}
	results := []i32{0, PAGE_SIZE / 2, -i32(linux.Errno.EIO), -i32(linux.Errno.ECANCELED)}
	for op in ops {
		for res in results {
			s := make_close_test_io(t, 0)
			s.slots[1].state = op == .READ ? .Open : .Dirty
			ud := rifle.UringUserData{op = op, file_slot = 1, page_index = 42, payload = 123}
			s.cqes[0] = {user_data = cast(u64)ud, res = res}
			// A full caller buffer must not consume the completion.
			n, err := rifle.uring_poll(&s.io, nil)
			testing.expect(t, err == nil && n == 0 && s.cq_head == 0)
			completions: [1]rifle.IOCompletion
			n, err = rifle.uring_poll(&s.io, completions[:])
			extra_require(t, err == nil && n == 1)
			testing.expect_value(t, completions[0].res, res)
			testing.expect_value(t, completions[0].user_data,
				rifle.IOUserData{op = op == .READ ? .READ : .WRITE, page_index = 42, payload = 123})
			n, err = rifle.uring_poll(&s.io, completions[:])
			testing.expect(t, err == nil && n == 0) // Ignore trailing link timeout.
		}
	}
}

@(test)
uring_reports_file_allocation_failure :: proc(t: ^testing.T) {
	s := make_close_test_io(t, 0)
	s.slots[1].state = .Opening
	s.cq_tail = 1
	ud := rifle.UringUserData{op = .ALLOCATE, file_slot = 1, page_index = 12, payload = 34}
	s.cqes[0] = {user_data = cast(u64)ud, res = -i32(linux.Errno.ENOSPC)}
	completions: [1]rifle.IOCompletion
	n, err := rifle.uring_poll(&s.io, completions[:])
	extra_require(t, err == nil && n == 1)
	testing.expect_value(t, completions[0].res, -i32(linux.Errno.ENOSPC))
	testing.expect_value(t, completions[0].user_data, rifle.IOUserData{op = .OPEN, page_index = 12, payload = 34})
	testing.expect(t, s.slots[1].state != .Open)
}

@(test)
uring_failed_open_releases_reserved_slot :: proc(t: ^testing.T) {
	s := make_close_test_io(t, 0)
	s.slots[1].state = .Opening
	ud := rifle.UringUserData{op = .OPEN, file_slot = 1}
	s.cqes[0] = {user_data = cast(u64)ud, res = -i32(linux.Errno.ENOENT)}
	ud.op = .ALLOCATE
	s.cqes[1] = {user_data = cast(u64)ud, res = -i32(linux.Errno.ECANCELED)}
	completions: [2]rifle.IOCompletion
	_, err := rifle.uring_poll(&s.io, completions[:])
	testing.expect(t, err == nil)
	// No fd was opened. The failed request must not permanently exhaust capacity.
	_, exists := s.io.file_index.file_map[901]
	testing.expect(t, !exists)
	testing.expect(t, s.slots[1].state == .Empty)
}
