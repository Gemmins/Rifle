package rifle

import "base:runtime"
import "core:sys/linux"
import "core:sys/posix"

// This is not useable as a general purpose allocator

FileBackedArena :: struct {
	file:           linux.Fd,
	size:           i64,
	allocator_head: i64,
	allocator_tail: i64,
	base:           [^]u8,
}

file_backed_arena_proc :: proc(
	allocator_data: rawptr,
	mode: runtime.Allocator_Mode,
	size, alignment: int,
	old_memory: rawptr,
	old_size: int,
	location := #caller_location,
) -> (
	data: []u8,
	err: runtime.Allocator_Error,
) {
	arena := cast(^FileBackedArena)allocator_data
	size := cast(i64)size

	if alignment != 0 {
		alignment := cast(i64)alignment
		thing := alignment - (arena.allocator_head % alignment)
		arena.allocator_head += thing
	}

	switch mode {
	case .Alloc, .Alloc_Non_Zeroed:
		if arena.allocator_head + size > arena.allocator_tail {
			return nil, .Out_Of_Memory
		}
		data = arena.base[arena.allocator_head:arena.allocator_head + size]
		arena.allocator_head += size
		return
	case .Free_All:
		error := linux.munmap(arena.base, cast(uint)size)
		if error != nil {
			err = .Invalid_Argument
		}
		return
	case .Free, .Query_Features, .Query_Info, .Resize, .Resize_Non_Zeroed:
		err = .Mode_Not_Implemented
	}

	return
}

alloc_from_end :: proc(arena: ^FileBackedArena, size: i64) -> ([]u8, runtime.Allocator_Error) {
	if size > arena.allocator_tail - arena.allocator_head {
		return nil, .Out_Of_Memory
	}
	data := arena.base[arena.allocator_tail - size:arena.allocator_tail]
	arena.allocator_tail -= size
	return data, nil
}

new_file_backed_arena :: proc(file: linux.Fd, size: i64) -> (runtime.Allocator, RifleError) {
	sys_page_size := posix.sysconf(._PAGE_SIZE)
	if size % sys_page_size != 0 {
		return {}, .GenericError
	}

	stat: linux.Stat
	errno := linux.fstat(file, &stat)
	if stat.size != 0 || errno != .NONE { 	// File should be empty
		return {}, .GenericError
	}

	errno = linux.ftruncate(file, size)
	if errno != .NONE {
		return {}, .GenericError
	}

	base, m_errno := linux.mmap(0, cast(uint)size, {.READ, .WRITE}, {.SHARED}, file, 0)
	if m_errno != .NONE {
		return {}, .GenericError
	}

	arena := FileBackedArena{file, size, 0, size, cast([^]u8)base}

	a := cast(^FileBackedArena)base
	a^ = arena
	a.allocator_head += size_of(FileBackedArena)

	return {file_backed_arena_proc, base}, nil
}

destroy_file_backed_arena :: proc(arena: ^FileBackedArena) -> RifleError {
	err := linux.munmap(arena.base, cast(uint)arena.size)
	if err != nil {
		return .GenericError
	}
	return nil
}
