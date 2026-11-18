package unit

import "core:sys/linux"
import "core:sys/linux/uring"
import "core:testing"
import rifle "rifle:rifle"

Test_Submission_Ring :: struct {
	ring:  uring.Ring,
	head:  u32,
	sqes:  [4]linux.IO_Uring_SQE,
}

init_test_submission_ring :: proc(s: ^Test_Submission_Ring) {
	s.ring.sq.head = &s.head
	s.ring.sq.mask = 3
	s.ring.sq.sqes = s.sqes[:]
}

@(test)
given_available_sqe_when_read_fixed_is_built_then_all_fields_are_populated :: proc(t: ^testing.T) {
	// Arrange
	s: Test_Submission_Ring
	init_test_submission_ring(&s)
	buffer: [32]u8

	// Act
	sqe, ok := rifle.read_fixed(&s.ring, 41, 7, buffer[:], 19, 2)

	// Assert
	testing.expect(t, ok)
	testing.expect(t, sqe != nil)
	testing.expect_value(t, sqe.opcode, linux.IO_Uring_OP.READ_FIXED)
	testing.expect_value(t, sqe.fd, linux.Fd(7))
	testing.expect_value(t, sqe.addr, cast(u64)uintptr(raw_data(buffer[:])))
	testing.expect_value(t, sqe.len, u32(32))
	testing.expect_value(t, sqe.off, u64(19))
	testing.expect_value(t, sqe.buf_index, u16(2))
	testing.expect_value(t, sqe.user_data, u64(41))
}

@(test)
given_available_sqe_when_write_fixed_is_built_then_all_fields_are_populated :: proc(t: ^testing.T) {
	// Arrange
	s: Test_Submission_Ring
	init_test_submission_ring(&s)
	buffer: [16]u8

	// Act
	sqe, ok := rifle.write_fixed(&s.ring, 42, 8, buffer[:], 20, 3)

	// Assert
	testing.expect(t, ok)
	testing.expect(t, sqe != nil)
	testing.expect_value(t, sqe.opcode, linux.IO_Uring_OP.WRITE_FIXED)
	testing.expect_value(t, sqe.fd, linux.Fd(8))
	testing.expect_value(t, sqe.addr, cast(u64)uintptr(raw_data(buffer[:])))
	testing.expect_value(t, sqe.len, u32(16))
	testing.expect_value(t, sqe.off, u64(20))
	testing.expect_value(t, sqe.buf_index, u16(3))
	testing.expect_value(t, sqe.user_data, u64(42))
}

@(test)
given_available_sqe_when_fallocate_is_built_then_length_and_mode_are_populated :: proc(t: ^testing.T) {
	// Arrange
	s: Test_Submission_Ring
	init_test_submission_ring(&s)
	mode := rifle.IO_Uring_Fallocate_Flags{.FALLOC_FL_KEEP_SIZE}

	// Act
	sqe, ok := rifle.fallocate(&s.ring, 43, 9, mode, 21, 8192)

	// Assert
	testing.expect(t, ok)
	testing.expect_value(t, sqe.opcode, linux.IO_Uring_OP.FALLOCATE)
	testing.expect_value(t, sqe.fd, linux.Fd(9))
	testing.expect_value(t, sqe.off, u64(21))
	testing.expect_value(t, sqe.addr, u64(8192))
	testing.expect_value(t, sqe.len, transmute(u32)mode)
	testing.expect_value(t, sqe.user_data, u64(43))
}

@(test)
given_available_sqe_when_unlinkat_is_built_then_path_and_flags_are_populated :: proc(t: ^testing.T) {
	// Arrange
	s: Test_Submission_Ring
	init_test_submission_ring(&s)
	path: cstring = "data.rfl"
	flags := rifle.IO_Uring_Unlinkat_Flags{.AT_REMOVEDIR}

	// Act
	sqe, ok := rifle.unlinkat(&s.ring, 44, 10, path, flags)

	// Assert
	testing.expect(t, ok)
	testing.expect_value(t, sqe.opcode, linux.IO_Uring_OP.UNLINKAT)
	testing.expect_value(t, sqe.fd, linux.Fd(10))
	testing.expect_value(t, sqe.addr, transmute(u64)path)
	testing.expect_value(t, sqe.unlink_flags, transmute(u32)flags)
	testing.expect_value(t, sqe.user_data, u64(44))
}

@(test)
given_full_submission_queue_when_operation_is_built_then_no_sqe_is_returned :: proc(t: ^testing.T) {
	// Arrange
	s: Test_Submission_Ring
	init_test_submission_ring(&s)
	s.ring.sq.sqe_tail = 4
	buffer: [1]u8

	// Act
	sqe, ok := rifle.read_fixed(&s.ring, 1, 1, buffer[:], 0, 0)

	// Assert
	testing.expect(t, !ok)
	testing.expect(t, sqe == nil)
	testing.expect_value(t, s.ring.sq.sqe_tail, u32(4))
}
