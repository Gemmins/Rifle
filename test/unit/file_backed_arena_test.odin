package unit

import "base:runtime"
import "core:sys/linux"
import "core:sys/posix"
import "core:testing"
import rifle "rifle:rifle"

Arena_Test_Owner :: struct {
	marker: u64,
	arena:  rifle.FileBackedArena,
}

@(test)
given_size_not_aligned_to_system_page_when_bootstrapped_then_request_is_rejected :: proc(t: ^testing.T) {
	// Arrange
	fd, create_err := linux.memfd_create("rifle-arena-size-test", {.CLOEXEC})
	if !testing.expect_value(t, create_err, linux.Errno.NONE) {
		return
	}
	defer linux.close(fd)
	page_size := i64(posix.sysconf(._PAGE_SIZE))

	// Act
	owner, err := rifle.file_backed_arena_bootstrap_by_name(Arena_Test_Owner, "arena", fd, page_size + 1)

	// Assert
	testing.expect(t, owner == nil)
	testing.expect_value(t, err, rifle.RifleError.GenericError)
}

@(test)
given_non_empty_file_when_bootstrapped_then_request_is_rejected :: proc(t: ^testing.T) {
	// Arrange
	fd, create_err := linux.memfd_create("rifle-arena-non-empty-test", {.CLOEXEC})
	if !testing.expect_value(t, create_err, linux.Errno.NONE) {
		return
	}
	defer linux.close(fd)
	page_size := i64(posix.sysconf(._PAGE_SIZE))
	truncate_err := linux.ftruncate(fd, page_size)
	if !testing.expect_value(t, truncate_err, linux.Errno.NONE) {
		return
	}

	// Act
	owner, err := rifle.file_backed_arena_bootstrap_by_name(Arena_Test_Owner, "arena", fd, page_size)

	// Assert
	testing.expect(t, owner == nil)
	testing.expect_value(t, err, rifle.RifleError.GenericError)
}

@(test)
given_empty_file_when_bootstrapped_then_owner_and_arena_share_mapping :: proc(t: ^testing.T) {
	// Arrange
	fd, create_err := linux.memfd_create("rifle-arena-bootstrap-test", {.CLOEXEC})
	if !testing.expect_value(t, create_err, linux.Errno.NONE) {
		return
	}
	defer linux.close(fd)
	page_size := i64(posix.sysconf(._PAGE_SIZE))

	// Act
	owner, err := rifle.file_backed_arena_bootstrap_by_name(Arena_Test_Owner, "arena", fd, page_size)
	if !testing.expect_value(t, err, rifle.RifleError.None) {
		return
	}
	defer rifle.destroy_file_backed_arena(&owner.arena)

	// Assert
	testing.expect(t, owner != nil)
	testing.expect_value(t, owner.arena.file, fd)
	testing.expect_value(t, owner.arena.size, page_size)
	testing.expect_value(t, owner.arena.allocator_head, i64(size_of(Arena_Test_Owner)))
	testing.expect_value(t, owner.arena.allocator_tail, page_size)
}

@(test)
given_bootstrapped_arena_when_front_allocations_are_made_then_alignment_and_bounds_are_honoured :: proc(t: ^testing.T) {
	// Arrange
	fd, create_err := linux.memfd_create("rifle-arena-front-test", {.CLOEXEC})
	if !testing.expect_value(t, create_err, linux.Errno.NONE) {
		return
	}
	defer linux.close(fd)
	page_size := i64(posix.sysconf(._PAGE_SIZE))
	owner, bootstrap_err := rifle.file_backed_arena_bootstrap_by_name(Arena_Test_Owner, "arena", fd, page_size)
	if !testing.expect_value(t, bootstrap_err, rifle.RifleError.None) {
		return
	}
	defer rifle.destroy_file_backed_arena(&owner.arena)
	allocator := runtime.Allocator{owner.arena.allocator_proc, &owner.arena}
	expected_offset := (i64(size_of(Arena_Test_Owner)) + 15) & ~i64(15)

	// Act
	first, first_err := allocator.procedure(allocator.data, .Alloc, 24, 16, nil, 0)
	second, second_err := allocator.procedure(allocator.data, .Alloc, int(page_size), 1, nil, 0)
	first_offset := i64(uintptr(raw_data(first))) - i64(uintptr(owner.arena.base))

	// Assert
	testing.expect_value(t, first_err, runtime.Allocator_Error.None)
	testing.expect_value(t, uintptr(raw_data(first)) % 16, uintptr(0))
	testing.expect_value(t, first_offset, expected_offset)
	testing.expect_value(t, len(first), 24)
	testing.expect_value(t, second_err, runtime.Allocator_Error.Out_Of_Memory)
	testing.expect(t, second == nil)
}

@(test)
given_bootstrapped_arena_when_allocating_from_end_then_front_space_is_not_crossed :: proc(t: ^testing.T) {
	// Arrange
	fd, create_err := linux.memfd_create("rifle-arena-tail-test", {.CLOEXEC})
	if !testing.expect_value(t, create_err, linux.Errno.NONE) {
		return
	}
	defer linux.close(fd)
	page_size := i64(posix.sysconf(._PAGE_SIZE))
	owner, bootstrap_err := rifle.file_backed_arena_bootstrap_by_name(Arena_Test_Owner, "arena", fd, page_size)
	if !testing.expect_value(t, bootstrap_err, rifle.RifleError.None) {
		return
	}
	defer rifle.destroy_file_backed_arena(&owner.arena)

	// Act
	tail, tail_err := rifle.alloc_from_end(&owner.arena, 128)
	remaining := owner.arena.allocator_tail - owner.arena.allocator_head
	overflow, overflow_err := rifle.alloc_from_end(&owner.arena, remaining + 1)

	// Assert
	testing.expect_value(t, tail_err, runtime.Allocator_Error.None)
	testing.expect_value(t, len(tail), 128)
	testing.expect_value(t, uintptr(raw_data(tail)), uintptr(owner.arena.base) + uintptr(page_size - 128))
	testing.expect_value(t, overflow_err, runtime.Allocator_Error.Out_Of_Memory)
	testing.expect(t, overflow == nil)
}

@(test)
given_aligned_allocator_head_when_allocating_then_no_extra_alignment_block_is_skipped :: proc(t: ^testing.T) {
	// Arrange
	fd, create_err := linux.memfd_create("rifle-arena-aligned-head-test", {.CLOEXEC})
	if !testing.expect_value(t, create_err, linux.Errno.NONE) {
		return
	}
	defer linux.close(fd)
	page_size := i64(posix.sysconf(._PAGE_SIZE))
	owner, bootstrap_err := rifle.file_backed_arena_bootstrap_by_name(Arena_Test_Owner, "arena", fd, page_size)
	if !testing.expect_value(t, bootstrap_err, rifle.RifleError.None) {
		return
	}
	defer rifle.destroy_file_backed_arena(&owner.arena)
	allocator := runtime.Allocator{owner.arena.allocator_proc, &owner.arena}
	initial_head := owner.arena.allocator_head
	alignment := int(align_of(Arena_Test_Owner))
	if !testing.expect_value(t, initial_head % i64(alignment), i64(0)) {
		return
	}

	// Act
	allocation, err := allocator.procedure(allocator.data, .Alloc, 16, alignment, nil, 0)
	offset := i64(uintptr(raw_data(allocation))) - i64(uintptr(owner.arena.base))

	// Assert
	testing.expect_value(t, err, runtime.Allocator_Error.None)
	testing.expect_value(t, offset, initial_head)
}
