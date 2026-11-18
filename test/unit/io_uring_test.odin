package unit

import "core:sys/linux"
import "core:sys/linux/uring"
import "core:testing"
import rifle "rifle:rifle"

Synthetic_Uring :: struct {
	io:       rifle.UringIO,
	sq_head:  u32,
	sq_flags: linux.IO_Uring_Submission_Queue_Flags,
	cq_head:  u32,
	cq_tail:  u32,
	sqes:     [8]linux.IO_Uring_SQE,
	cqes:     [8]linux.IO_Uring_CQE,
	slots:    [2]rifle.FileSlot,
	free:     [2]u16,
	paths:    [8][len(rifle.DATA_PREFIX) + 20 + len(rifle.FILE_EXTENSION) + 1]u8,
}

init_synthetic_uring :: proc(s: ^Synthetic_Uring) {
	s.io.config.file_size = 8192
	s.io.paths = s.paths[:]
	s.io.file_index.slots = s.slots[:]
	s.io.file_index.file_map = make(map[i64]u16)
	s.io.file_index.slot_stack = {top = 2, data = s.free[:]}
	s.free = {0, 1}
	s.io.ring.sq.head = &s.sq_head
	s.io.ring.sq.flags = &s.sq_flags
	s.io.ring.sq.mask = 7
	s.io.ring.sq.sqes = s.sqes[:]
	s.io.ring.cq.head = &s.cq_head
	s.io.ring.cq.tail = &s.cq_tail
	s.io.ring.cq.mask = 7
	s.io.ring.cq.cqes = s.cqes[:]
}

destroy_synthetic_uring :: proc(s: ^Synthetic_Uring) {
	delete(s.io.file_index.file_map)
}

synthetic_register :: proc(s: ^Synthetic_Uring, file_id: i64, state: rifle.FileState) -> u16 {
	slot, ok := rifle.register_file(&s.io.file_index, file_id)
	assert(ok)
	s.slots[slot].state = state
	return slot
}

@(test)
given_uring_config_when_io_is_created_then_interface_is_fully_wired :: proc(t: ^testing.T) {
	// Arrange
	config := rifle.UringConfig{uring.DEFAULT_PARAMS, 4, 8192}

	// Act
	io := rifle.new_uring_io(config, 12)
	implementation := cast(^rifle.UringIO)io.data

	// Assert
	testing.expect(t, implementation != nil)
	testing.expect_value(t, implementation.config, config)
	testing.expect_value(t, implementation.dirfd, linux.Fd(12))
	testing.expect(t, io.init != nil)
	testing.expect(t, io.deinit != nil)
	testing.expect(t, io.open != nil)
	testing.expect(t, io.close != nil)
	testing.expect(t, io.read_at != nil)
	testing.expect(t, io.write_at != nil)
	testing.expect(t, io.write_header != nil)
	testing.expect(t, io.sync != nil)
	testing.expect(t, io.unlink != nil)
	testing.expect(t, io.poll != nil)

	free(io.data)
}

@(test)
given_file_slots_when_files_are_registered_and_removed_then_ownership_is_unique_and_reusable :: proc(t: ^testing.T) {
	// Arrange
	s: Synthetic_Uring
	init_synthetic_uring(&s)
	defer destroy_synthetic_uring(&s)

	// Act
	first_slot, first_ok := rifle.register_file(&s.io.file_index, 10)
	_, duplicate_ok := rifle.register_file(&s.io.file_index, 10)
	second_slot, second_ok := rifle.register_file(&s.io.file_index, 20)
	_, exhausted_ok := rifle.register_file(&s.io.file_index, 30)
	rifle.remove_file(&s.io.file_index, first_slot)
	reused_slot, reused_ok := rifle.register_file(&s.io.file_index, 30)

	// Assert
	testing.expect(t, first_ok)
	testing.expect(t, second_ok)
	testing.expect(t, !duplicate_ok)
	testing.expect(t, !exhausted_ok)
	testing.expect(t, reused_ok)
	testing.expect(t, first_slot != second_slot)
	testing.expect_value(t, reused_slot, first_slot)
	testing.expect_value(t, s.slots[reused_slot].file_id, i64(30))
	testing.expect_value(t, len(s.io.file_index.file_map), 2)
}

@(test)
given_available_queue_and_slot_when_file_is_opened_then_linked_operation_chain_is_built :: proc(t: ^testing.T) {
	// Arrange
	s: Synthetic_Uring
	init_synthetic_uring(&s)
	defer destroy_synthetic_uring(&s)
	request := rifle.IOUserData{op = .OPEN, page_index = 7, payload = 99}

	// Act
	err := rifle.uring_open(&s.io, request, 42)
	slot, registered := s.io.file_index.file_map[42]
	path := string(transmute(cstring)s.sqes[0].addr)

	// Assert
	testing.expect_value(t, err, rifle.RifleError.None)
	testing.expect(t, registered)
	testing.expect_value(t, s.io.ring.sq.sqe_tail, u32(3))
	testing.expect_value(t, s.sqes[0].opcode, linux.IO_Uring_OP.OPENAT)
	testing.expect_value(t, s.sqes[1].opcode, linux.IO_Uring_OP.FALLOCATE)
	testing.expect_value(t, s.sqes[2].opcode, linux.IO_Uring_OP.LINK_TIMEOUT)
	testing.expect(t, .IO_LINK in s.sqes[0].flags)
	testing.expect(t, .IO_LINK in s.sqes[1].flags)
	testing.expect(t, .FIXED_FILE in s.sqes[1].flags)
	testing.expect_value(t, s.sqes[0].file_index, u32(slot) + 1)
	testing.expect_value(t, path, "data_00000000000000000042.rfl")
	testing.expect_value(t, s.slots[slot].state, rifle.FileState.Opening)
}

@(test)
given_insufficient_queue_space_when_file_is_opened_then_no_slot_or_sqe_is_claimed :: proc(t: ^testing.T) {
	// Arrange
	s: Synthetic_Uring
	init_synthetic_uring(&s)
	defer destroy_synthetic_uring(&s)
	s.io.ring.sq.sqe_tail = 6

	// Act
	err := rifle.uring_open(&s.io, {}, 42)
	_, registered := s.io.file_index.file_map[42]

	// Assert
	testing.expect_value(t, err, rifle.RifleError.GenericError)
	testing.expect(t, !registered)
	testing.expect_value(t, s.io.ring.sq.sqe_tail, u32(6))
	testing.expect_value(t, s.io.file_index.slot_stack.top, i64(2))
}

@(test)
given_unregistered_file_when_written_then_open_allocate_write_and_timeout_are_linked :: proc(t: ^testing.T) {
	// Arrange
	s: Synthetic_Uring
	init_synthetic_uring(&s)
	defer destroy_synthetic_uring(&s)
	buffer: [4096]u8
	request := rifle.IOUserData{op = .WRITE, page_index = 5, payload = 77}

	// Act
	err := rifle.uring_writeat(&s.io, request, buffer[:], 4096, 51)
	slot, registered := s.io.file_index.file_map[51]

	// Assert
	testing.expect_value(t, err, rifle.RifleError.None)
	testing.expect(t, registered)
	testing.expect_value(t, s.io.ring.sq.sqe_tail, u32(4))
	testing.expect_value(t, s.sqes[0].opcode, linux.IO_Uring_OP.OPENAT)
	testing.expect_value(t, s.sqes[1].opcode, linux.IO_Uring_OP.FALLOCATE)
	testing.expect_value(t, s.sqes[2].opcode, linux.IO_Uring_OP.WRITE_FIXED)
	testing.expect_value(t, s.sqes[3].opcode, linux.IO_Uring_OP.LINK_TIMEOUT)
	testing.expect_value(t, s.sqes[2].off, u64(4096))
	testing.expect_value(t, s.sqes[2].buf_index, u16(1))
	testing.expect_value(t, s.slots[slot].state, rifle.FileState.OpeningDirty)
}

@(test)
given_opening_file_when_read_or_write_is_requested_then_file_not_ready_is_returned :: proc(t: ^testing.T) {
	// Arrange
	s: Synthetic_Uring
	init_synthetic_uring(&s)
	defer destroy_synthetic_uring(&s)
	_ = synthetic_register(&s, 61, .Opening)
	buffer: [4096]u8

	// Act
	read_err := rifle.uring_readat(&s.io, {}, buffer[:], 0, 61)
	write_err := rifle.uring_writeat(&s.io, {}, buffer[:], 0, 61)

	// Assert
	testing.expect_value(t, read_err, rifle.RifleError.FileNotReady)
	testing.expect_value(t, write_err, rifle.RifleError.FileNotReady)
	testing.expect_value(t, s.io.ring.sq.sqe_tail, u32(0))
}

@(test)
given_dirty_files_and_header_when_sync_is_requested_then_every_target_is_queued_as_one_batch :: proc(t: ^testing.T) {
	// Arrange
	s: Synthetic_Uring
	init_synthetic_uring(&s)
	defer destroy_synthetic_uring(&s)
	first := synthetic_register(&s, 71, .Dirty)
	second := synthetic_register(&s, 72, .OpeningDirty)
	s.io.header_dirty = true
	request := rifle.IOUserData{op = .SYNC, page_index = 9, payload = 88}

	// Act
	err := rifle.uring_sync(&s.io, request)

	// Assert
	testing.expect_value(t, err, rifle.RifleError.None)
	testing.expect(t, s.io.sync_pending)
	testing.expect_value(t, s.io.pending_syncs, u32(3))
	testing.expect_value(t, s.io.ring.sq.sqe_tail, u32(6))
	testing.expect_value(t, s.slots[first].state, rifle.FileState.Flushing)
	testing.expect_value(t, s.slots[second].state, rifle.FileState.Flushing)
	testing.expect(t, !s.io.header_dirty)
	for i in 0 ..< 3 {
		testing.expect_value(t, s.sqes[i * 2 + 1].opcode, linux.IO_Uring_OP.LINK_TIMEOUT)
	}
}

@(test)
given_allocate_completion_when_polled_then_public_open_completion_and_file_state_are_restored :: proc(t: ^testing.T) {
	// Arrange
	s: Synthetic_Uring
	init_synthetic_uring(&s)
	defer destroy_synthetic_uring(&s)
	slot := synthetic_register(&s, 81, .OpeningDirty)
	internal := rifle.UringUserData{page_index = 12, file_slot = slot, op = .ALLOCATE, payload = 91}
	s.cqes[0] = {user_data = cast(u64)internal, res = 0}
	s.cq_tail = 1
	completions: [1]rifle.IOCompletion

	// Act
	count, err := rifle.uring_poll(&s.io, completions[:])

	// Assert
	testing.expect_value(t, err, rifle.RifleError.None)
	testing.expect_value(t, count, u32(1))
	testing.expect_value(t, completions[0].user_data, rifle.IOUserData{page_index = 12, op = .OPEN, payload = 91})
	testing.expect_value(t, completions[0].res, i32(0))
	testing.expect_value(t, s.slots[slot].state, rifle.FileState.Dirty)
	testing.expect_value(t, s.cq_head, u32(1))
}

@(test)
given_successful_close_completion_when_polled_then_slot_is_returned_and_token_is_preserved :: proc(t: ^testing.T) {
	// Arrange
	s: Synthetic_Uring
	init_synthetic_uring(&s)
	defer destroy_synthetic_uring(&s)
	slot := synthetic_register(&s, 82, .Closing)
	internal := rifle.UringUserData{page_index = 13, file_slot = slot, op = .CLOSE, payload = 92}
	s.cqes[0] = {user_data = cast(u64)internal, res = 0}
	s.cq_tail = 1
	completions: [1]rifle.IOCompletion

	// Act
	count, err := rifle.uring_poll(&s.io, completions[:])
	_, registered := s.io.file_index.file_map[82]

	// Assert
	testing.expect_value(t, err, rifle.RifleError.None)
	testing.expect_value(t, count, u32(1))
	testing.expect_value(t, completions[0].user_data, rifle.IOUserData{page_index = 13, op = .CLOSE, payload = 92})
	testing.expect(t, !registered)
	testing.expect_value(t, s.slots[slot].state, rifle.FileState.Empty)
	testing.expect_value(t, s.io.file_index.slot_stack.top, i64(2))
}

@(test)
given_completed_sync_batch_when_polled_then_single_public_completion_advances_state :: proc(t: ^testing.T) {
	// Arrange
	s: Synthetic_Uring
	init_synthetic_uring(&s)
	defer destroy_synthetic_uring(&s)
	slot := synthetic_register(&s, 83, .Flushing)
	s.io.sync_pending = true
	s.io.pending_syncs = 1
	s.io.sync_completion = {user_data = {op = .SYNC, page_index = 14, payload = 93}}
	internal := rifle.UringUserData{file_slot = slot, op = .SYNC}
	s.cqes[0] = {user_data = cast(u64)internal, res = 0}
	s.cq_tail = 1
	completions: [1]rifle.IOCompletion

	// Act
	count, err := rifle.uring_poll(&s.io, completions[:])

	// Assert
	testing.expect_value(t, err, rifle.RifleError.None)
	testing.expect_value(t, count, u32(1))
	testing.expect_value(t, completions[0].user_data, rifle.IOUserData{op = .SYNC, page_index = 14, payload = 93})
	testing.expect_value(t, completions[0].res, i32(0))
	testing.expect_value(t, s.slots[slot].state, rifle.FileState.Open)
	testing.expect(t, !s.io.sync_pending)
	testing.expect_value(t, s.io.pending_syncs, u32(0))
}

@(test)
given_open_file_when_read_and_write_are_requested_then_fixed_buffer_operations_are_linked_and_file_becomes_dirty :: proc(t: ^testing.T) {
	// Arrange
	s: Synthetic_Uring
	init_synthetic_uring(&s)
	defer destroy_synthetic_uring(&s)
	slot := synthetic_register(&s, 91, .Open)
	read_buffer: [4096]u8
	write_buffer: [4096]u8

	// Act
	read_err := rifle.uring_readat(&s.io, {op = .READ, page_index = 3}, read_buffer[:], 4096, 91)
	write_err := rifle.uring_writeat(&s.io, {op = .WRITE, page_index = 4}, write_buffer[:], 0, 91)

	// Assert
	testing.expect_value(t, read_err, rifle.RifleError.None)
	testing.expect_value(t, write_err, rifle.RifleError.None)
	testing.expect_value(t, s.io.ring.sq.sqe_tail, u32(4))
	testing.expect_value(t, s.sqes[0].opcode, linux.IO_Uring_OP.READ_FIXED)
	testing.expect_value(t, s.sqes[1].opcode, linux.IO_Uring_OP.LINK_TIMEOUT)
	testing.expect_value(t, s.sqes[2].opcode, linux.IO_Uring_OP.WRITE_FIXED)
	testing.expect_value(t, s.sqes[3].opcode, linux.IO_Uring_OP.LINK_TIMEOUT)
	testing.expect(t, .FIXED_FILE in s.sqes[0].flags)
	testing.expect(t, .FIXED_FILE in s.sqes[2].flags)
	testing.expect_value(t, s.sqes[0].buf_index, u16(0))
	testing.expect_value(t, s.sqes[2].buf_index, u16(1))
	testing.expect_value(t, s.slots[slot].state, rifle.FileState.Dirty)
}

@(test)
given_open_clean_file_when_close_is_requested_then_drained_close_and_timeout_are_linked :: proc(t: ^testing.T) {
	// Arrange
	s: Synthetic_Uring
	init_synthetic_uring(&s)
	defer destroy_synthetic_uring(&s)
	slot := synthetic_register(&s, 92, .Open)

	// Act
	err := rifle.uring_close(&s.io, {op = .CLOSE, payload = 17}, 92)

	// Assert
	testing.expect_value(t, err, rifle.RifleError.None)
	testing.expect_value(t, s.io.ring.sq.sqe_tail, u32(2))
	testing.expect_value(t, s.sqes[0].opcode, linux.IO_Uring_OP.CLOSE)
	testing.expect_value(t, s.sqes[1].opcode, linux.IO_Uring_OP.LINK_TIMEOUT)
	testing.expect(t, .IO_LINK in s.sqes[0].flags)
	testing.expect(t, .IO_DRAIN in s.sqes[0].flags)
	testing.expect_value(t, s.slots[slot].state, rifle.FileState.Closing)
}

@(test)
given_header_buffer_when_write_is_requested_then_header_write_and_timeout_are_linked :: proc(t: ^testing.T) {
	// Arrange
	s: Synthetic_Uring
	init_synthetic_uring(&s)
	defer destroy_synthetic_uring(&s)
	s.io.header_fd = 23
	buffer: [16]u8

	// Act
	err := rifle.uring_write_header(&s.io, {op = .HEADER, payload = 18}, buffer[:])

	// Assert
	testing.expect_value(t, err, rifle.RifleError.None)
	testing.expect_value(t, s.io.ring.sq.sqe_tail, u32(2))
	testing.expect_value(t, s.sqes[0].opcode, linux.IO_Uring_OP.WRITE_FIXED)
	testing.expect_value(t, s.sqes[1].opcode, linux.IO_Uring_OP.LINK_TIMEOUT)
	testing.expect_value(t, s.sqes[0].fd, linux.Fd(23))
	testing.expect_value(t, s.sqes[0].off, u64(rifle.BASE_FILE_PREFIX_SIZE - 2 * size_of(i64)))
	testing.expect(t, .IO_LINK in s.sqes[0].flags)
	testing.expect(t, s.io.header_dirty)
}

@(test)
given_file_index_when_unlink_is_requested_then_formatted_path_and_timeout_are_linked :: proc(t: ^testing.T) {
	// Arrange
	s: Synthetic_Uring
	init_synthetic_uring(&s)
	defer destroy_synthetic_uring(&s)
	s.io.dirfd = 24

	// Act
	err := rifle.uring_unlink(&s.io, {op = .DELETE, payload = 19}, 93)
	path := string(transmute(cstring)s.sqes[0].addr)

	// Assert
	testing.expect_value(t, err, rifle.RifleError.None)
	testing.expect_value(t, s.io.ring.sq.sqe_tail, u32(2))
	testing.expect_value(t, s.sqes[0].opcode, linux.IO_Uring_OP.UNLINKAT)
	testing.expect_value(t, s.sqes[1].opcode, linux.IO_Uring_OP.LINK_TIMEOUT)
	testing.expect_value(t, s.sqes[0].fd, linux.Fd(24))
	testing.expect_value(t, path, "data_00000000000000000093.rfl")
	testing.expect(t, .IO_LINK in s.sqes[0].flags)
}

@(test)
given_sync_with_no_dirty_targets_when_polled_then_completion_is_reported_without_kernel_operations :: proc(t: ^testing.T) {
	// Arrange
	s: Synthetic_Uring
	init_synthetic_uring(&s)
	defer destroy_synthetic_uring(&s)
	request := rifle.IOUserData{op = .SYNC, page_index = 21, payload = 94}
	completions: [1]rifle.IOCompletion

	// Act
	sync_err := rifle.uring_sync(&s.io, request)
	count, poll_err := rifle.uring_poll(&s.io, completions[:])

	// Assert
	testing.expect_value(t, sync_err, rifle.RifleError.None)
	testing.expect_value(t, poll_err, rifle.RifleError.None)
	testing.expect_value(t, s.io.ring.sq.sqe_tail, u32(0))
	testing.expect_value(t, count, u32(1))
	testing.expect_value(t, completions[0].user_data, request)
	testing.expect_value(t, completions[0].res, i32(0))
	testing.expect(t, !s.io.sync_pending)
}

@(test)
given_failed_open_completion_when_polled_then_reserved_file_slot_is_released :: proc(t: ^testing.T) {
	// Arrange
	s: Synthetic_Uring
	init_synthetic_uring(&s)
	defer destroy_synthetic_uring(&s)
	slot := synthetic_register(&s, 94, .Opening)
	internal := rifle.UringUserData{file_slot = slot, op = .OPEN}
	s.cqes[0] = {user_data = cast(u64)internal, res = -i32(linux.Errno.ENOENT)}
	s.cq_tail = 1
	completions: [1]rifle.IOCompletion

	// Act
	count, err := rifle.uring_poll(&s.io, completions[:])
	_, registered := s.io.file_index.file_map[94]

	// Assert
	testing.expect_value(t, err, rifle.RifleError.None)
	testing.expect_value(t, count, u32(0))
	testing.expect(t, !registered)
	testing.expect_value(t, s.slots[slot].state, rifle.FileState.Empty)
	testing.expect_value(t, s.io.file_index.slot_stack.top, i64(2))
}

@(test)
given_failed_file_and_header_syncs_when_polled_then_dirty_state_is_restored_and_one_failure_is_reported :: proc(t: ^testing.T) {
	// Arrange
	s: Synthetic_Uring
	init_synthetic_uring(&s)
	defer destroy_synthetic_uring(&s)
	slot := synthetic_register(&s, 95, .Flushing)
	s.io.sync_pending = true
	s.io.pending_syncs = 2
	s.io.sync_completion = {user_data = {op = .SYNC, page_index = 22, payload = 95}}
	file_sync := rifle.UringUserData{file_slot = slot, op = .SYNC}
	header_sync := rifle.UringUserData{op = .HEADER_SYNC}
	s.cqes[0] = {user_data = cast(u64)file_sync, res = -i32(linux.Errno.EIO)}
	s.cqes[1] = {user_data = cast(u64)header_sync, res = -i32(linux.Errno.EIO)}
	s.cq_tail = 2
	completions: [1]rifle.IOCompletion

	// Act
	count, err := rifle.uring_poll(&s.io, completions[:])

	// Assert
	testing.expect_value(t, err, rifle.RifleError.None)
	testing.expect_value(t, count, u32(1))
	testing.expect_value(t, completions[0].user_data, rifle.IOUserData{op = .SYNC, page_index = 22, payload = 95})
	testing.expect_value(t, completions[0].res, -i32(linux.Errno.EIO))
	testing.expect_value(t, s.slots[slot].state, rifle.FileState.Dirty)
	testing.expect(t, s.io.header_dirty)
	testing.expect(t, !s.io.sync_pending)
	testing.expect_value(t, s.io.pending_syncs, u32(0))
}

@(test)
given_larger_uring_capacities_when_arena_size_is_calculated_then_required_space_increases :: proc(t: ^testing.T) {
	// Arrange
	files := u16(2)
	entries := 8
	buffers := 2

	// Act
	base := rifle.uring_io_arena_size(files, entries, buffers)
	more_files := rifle.uring_io_arena_size(files * 2, entries, buffers)
	more_entries := rifle.uring_io_arena_size(files, entries * 2, buffers)
	more_buffers := rifle.uring_io_arena_size(files, entries, buffers * 2)

	// Assert
	testing.expect(t, base > 0)
	testing.expect(t, more_files > base)
	testing.expect(t, more_entries > base)
	testing.expect(t, more_buffers > base)
}
