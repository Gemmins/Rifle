package rifle

import "core:sys/linux"
import "core:sys/linux/uring"

// TODO: Useful errors. Need to make RifleError into tagged union or smthn

UringIO :: struct {
	ring:       uring.Ring,
	config:     UringConfig,
	buffer:     []u8,
	file_index: FileIndex,
	op_timeout: linux.Time_Spec,
	dirfd:      linux.Fd,
}

UringConfig :: struct {
	params:    linux.IO_Uring_Params,
	num_files: u16, // MAX 1 << 12
	file_size: u64,
}

FileIndex :: struct {
	file_descriptors: []linux.Fd,
	file_states:      []FileState,
	cache_indices:    []u16,
	file_map:         map[i64]u16,
	slot_stack:       Stack(u16),
}

FileState :: enum u8 {
	Empty,
	Opening,
	Open,
	Dirty,
	Flushing,
	Closing,
}

Iovec :: struct {
	iov_base: [^]u8,
	iov_len:  uintptr,
}

UringUserData :: bit_field u64 {
	page_index: u32     | 24,
	file_index: u16     | 12,
	op:         UringOp | 4,
	payload:    u32     | 24,
}

UringOp :: enum u8 {
	OPEN,
	CLOSE,
	READ,
	WRITE,
	SYNC,
	DELETE,
	ALLOCATE,
	TIMEOUT,
}


get_file_slot :: proc(files: ^FileIndex, file: RifleFile) -> (u16, bool) {
	return files.file_map[file.id]
}

register_file :: proc(files: ^FileIndex, file: RifleFile, cache_index: u16) -> (u16, bool) {
	slot, ok := stack_pop(&files.slot_stack)
	if !ok {
		return 0, false
	}

	assert(u32(slot) < (1 << 12))

	files.file_map[file.id] = slot
	files.cache_indices[slot] = cache_index

	return slot, true
}

remove_file :: proc(files: ^FileIndex, file: RifleFile) -> bool {
	slot, ok := files.file_map[file.id]
	if !ok {
		return false
	}

	if !stack_push(&files.slot_stack, slot) {
		return false
	}

	_, _ = delete_key(&files.file_map, file.id)
	files.file_states[slot] = .Empty
	files.cache_indices[slot] = 0

	return true
}

link_timeout :: proc(
	ring: ^uring.Ring,
	user_data: UringUserData,
	ts: ^linux.Time_Spec,
	flags: linux.IO_Uring_Timeout_Flags,
) -> (
	^linux.IO_Uring_SQE,
	RifleError,
) {
	ud := user_data
	ud.op = .TIMEOUT
	sqe, ok := uring.link_timeout(ring, cast(u64)ud, ts, flags)
	if !ok {
		return nil, .GenericError
	}
	return sqe, nil
}

new_uring_io :: proc(config: UringConfig) -> IO {
	uring_io := new(UringIO, context.allocator)
	uring_io.config = config
	io := IO{rawptr(uring_io), uring_init, uring_deinit, uring_open, uring_close, uring_readat, uring_writeat, uring_sync, uring_delete, uring_poll}

	return io
}

uring_init :: proc(ctx: rawptr, cache_buffer: []u8) -> RifleError {
	io := cast(^UringIO)ctx
	io.op_timeout.time_sec = 60
	err := uring.init(&io.ring, &io.config.params)
	if err != nil {
		return .GenericError
	}

	io.buffer = cache_buffer

	iovec := Iovec{raw_data(io.buffer), cast(uintptr)len(io.buffer)}

	errno1 := linux.io_uring_register(io.ring.fd, linux.IO_Uring_Register_Opcode.REGISTER_BUFFERS, cast(rawptr)&iovec, 1)
	if errno1 != .NONE {
		return .GenericError
	}

	io.file_index.file_descriptors, _ = make([]linux.Fd, io.config.num_files, context.allocator)
	io.file_index.file_map, _ = make(map[i64]u16, io.config.num_files, context.allocator)
	io.file_index.file_states, _ = make([]FileState, io.config.num_files, context.allocator)
	io.file_index.cache_indices, _ = make([]u16, io.config.num_files, context.allocator)
	_ = stack_init(&io.file_index.slot_stack, cast(i64)io.config.num_files)
	for i in 0 ..< io.config.num_files {
		io.file_index.file_descriptors[i] = -1
		stack_push(&io.file_index.slot_stack, i)
	}

	errno2 := linux.io_uring_register(
		io.ring.fd,
		linux.IO_Uring_Register_Opcode.REGISTER_FILES,
		raw_data(io.file_index.file_descriptors),
		cast(u32)io.config.num_files,
	)
	if errno2 != .NONE {
		return .GenericError
	}

	return nil
}

uring_deinit :: proc(ctx: rawptr) -> RifleError {
	io := cast(^UringIO)ctx

	err := linux.io_uring_register(io.ring.fd, linux.IO_Uring_Register_Opcode.UNREGISTER_BUFFERS, nil, 0)
	if err != .NONE {
		return .GenericError
	}

	uring.destroy(&io.ring)

	_ = delete(io.file_index.file_descriptors)
	_ = delete(io.file_index.file_map)
	_ = delete(io.file_index.file_states)
	_ = delete(io.file_index.cache_indices)
	stack_deinit(&io.file_index.slot_stack)
	_ = free(io)

	return nil
}

//TODO: need to use registered file in known slot to link with falloc
uring_open :: proc(ctx: rawptr, user_data: IOUserData, file: RifleFile) -> RifleError {
	io := cast(^UringIO)ctx
	ud := cast(UringUserData)user_data

	file_slot, _ := register_file(&io.file_index, file, user_data.file_index) //TODO: maybe check for file already open
	ud.file_index = file_slot

	ud.op = .OPEN
	open_sqe, open_ok := uring.openat(&io.ring, cast(u64)ud, io.dirfd, file.path, {}, {.CREAT, .DIRECT, .RDWR}, cast(u32)file_slot + 1)
	if !open_ok {
		return .GenericError
	}
	open_sqe.flags |= {.IO_LINK}

	ud.op = .ALLOCATE
	falloc_sqe, falloc_ok := fallocate(&io.ring, cast(u64)ud, cast(linux.Fd)file_slot, {}, 0, io.config.file_size)
	if !falloc_ok {
		return .GenericError
	}
	falloc_sqe.flags |= {.IO_LINK, .FIXED_FILE}

	link_timeout(&io.ring, ud, &io.op_timeout, {}) or_return

	io.file_index.file_states[file_slot] = .Opening

	return nil
}

uring_close :: proc(ctx: rawptr, user_data: IOUserData, file: RifleFile) -> RifleError {
	io := cast(^UringIO)ctx
	ud := cast(UringUserData)user_data

	file_slot, exists := get_file_slot(&io.file_index, file)
	if !exists {
		return .GenericError
	}
	ud.file_index = file_slot

	ud.op = .CLOSE
	sqe, ok := uring.close(&io.ring, cast(u64)ud, 0, cast(u32)file_slot + 1)
	if !ok {
		return .GenericError
	}
	sqe.flags |= {.IO_LINK}

	link_timeout(&io.ring, ud, &io.op_timeout, {}) or_return

	io.file_index.file_states[file_slot] = .Closing

	return nil
}

uring_readat :: proc(ctx: rawptr, user_data: IOUserData, buffer: []u8, offset: u64, file: RifleFile) -> RifleError {
	io := cast(^UringIO)ctx
	ud := cast(UringUserData)user_data

	file_slot, exists := get_file_slot(&io.file_index, file)

	if !exists { 	// Do we need to check the state? If the file is "opening" what do we do? Is that even a state we can reach. Idk. Should the cache protect this?
		file_slot, _ = register_file(&io.file_index, file, user_data.file_index)
		ud.file_index = file_slot
		ud.op = .OPEN
		open_sqe, open_ok := uring.openat(&io.ring, cast(u64)ud, io.dirfd, file.path, {}, {.DIRECT, .RDWR}, cast(u32)file_slot)
		if !open_ok {
			return .GenericError
		}
		open_sqe.flags |= {.IO_LINK}
		io.file_index.file_states[file_slot] = .Opening
	}

	ud.file_index = file_slot
	ud.op = .READ
	sqe, ok := read_fixed(&io.ring, cast(u64)ud, cast(linux.Fd)file_slot, buffer, offset, 0)
	if !ok {
		return .GenericError
	}
	sqe.flags |= {.IO_LINK, .FIXED_FILE}

	link_timeout(&io.ring, ud, &io.op_timeout, {}) or_return

	return nil
}

uring_writeat :: proc(ctx: rawptr, user_data: IOUserData, buffer: []u8, offset: u64, file: RifleFile) -> RifleError {
	io := cast(^UringIO)ctx
	ud := cast(UringUserData)user_data

	file_slot, exists := get_file_slot(&io.file_index, file)

	if !exists {
		file_slot, _ = register_file(&io.file_index, file, user_data.file_index)
		ud.file_index = file_slot
		ud.op = .OPEN
		open_sqe, open_ok := uring.openat(&io.ring, cast(u64)ud, io.dirfd, file.path, {}, {.DIRECT, .RDWR, .CREAT}, cast(u32)file_slot)
		if !open_ok {
			return .GenericError
		}
		open_sqe.flags |= {.IO_LINK}
		io.file_index.file_states[file_slot] = .Opening
	}

	ud.file_index = file_slot
	ud.op = .WRITE
	sqe, ok := write_fixed(&io.ring, cast(u64)ud, cast(linux.Fd)file_slot, buffer, offset, 0)
	if !ok {
		return .GenericError
	}
	sqe.flags |= {.IO_LINK, .FIXED_FILE}
	io.file_index.file_states[file_slot] = .Dirty
	link_timeout(&io.ring, ud, &io.op_timeout, {}) or_return

	return nil
}

uring_sync :: proc(ctx: rawptr, user_data: IOUserData) -> RifleError {
	io := cast(^UringIO)ctx
	ud := cast(UringUserData)user_data

	files := stack_peek_all(&io.file_index.slot_stack)
	ud.op = .SYNC
	flags := linux.IO_Uring_Fsync_Flags{.DATASYNC}
	first := true
	for i in 0 ..< len(files) {
		if io.file_index.file_states[files[i]] == .Dirty {
			ud.file_index = files[i]
			sqe, ok := uring.fsync(&io.ring, cast(u64)ud, cast(linux.Fd)files[i], flags)
			if !ok {
				return .GenericError
			}
			if first {
				sqe.flags |= {.IO_DRAIN}
				first = false
			}
			sqe.flags |= {.FIXED_FILE, .IO_LINK}

			link_timeout(&io.ring, ud, &io.op_timeout, {}) or_return
		}
	}

	return nil
}

uring_delete :: proc(ctx: rawptr, user_data: IOUserData, file: RifleFile) -> RifleError {
	io := cast(^UringIO)ctx
	ud := cast(UringUserData)user_data

	ud.op = .DELETE
	sqe, ok := unlinkat(&io.ring, cast(u64)ud, io.dirfd, file.path, {})
	if !ok {
		return .GenericError
	}
	sqe.flags |= {.IO_LINK}

	link_timeout(&io.ring, ud, &io.op_timeout, {}) or_return

	return nil
}

uring_poll :: proc(ctx: rawptr, completions: []IOCompletion) -> (u32, RifleError) {
	io := cast(^UringIO)ctx

	if uring.sq_ready(&io.ring) > 0 {
		_, err := uring.submit(&io.ring, 0)

		if err != .NONE {
			return 0, .GenericError
		}
	}

	n := uring.cq_ready(&io.ring)
	head := io.ring.cq.head^
	mask := io.ring.cq.mask
	j: u32 = 0
	for i in 0 ..< n {
		cqe := &io.ring.cq.cqes[(head + i) & mask]

		completion := IOCompletion {
			user_data = cast(IOUserData)cqe.user_data,
			res       = cqe.res,
		}

		completion.user_data.file_index = io.file_index.cache_indices[completion.user_data.file_index]

		// Need to check actual success/ failure for these
		// For now just assuming success
		switch (cast(UringUserData)(cqe.user_data)).op {
		case .OPEN:
		case .CLOSE:
			io.file_index.file_states[completion.user_data.file_index] = .Empty
			completion.user_data.op = .CLOSE
			completions[j] = completion
			j += 1
		case .READ:
			completion.user_data.op = .READ
			completions[j] = completion
			j += 1
		case .WRITE:
			completion.user_data.op = .WRITE
			completions[j] = completion
			j += 1
		case .SYNC:
			if (io.file_index.file_states[completion.user_data.file_index] == .Flushing) { 	// Checks for no write in the mean time
				io.file_index.file_states[completion.user_data.file_index] = .Open
			}
			completions[j] = completion
			j += 1
		case .DELETE:
			completion.user_data.op = .DELETE
			completions[j] = completion
			j += 1
		case .ALLOCATE:
			io.file_index.file_states[completion.user_data.file_index] = .Open
			completion.user_data.op = .OPEN
			completions[j] = completion
			j += 1
		case .TIMEOUT:
		// Eventually do something here
		}
	}

	uring.cq_advance(&io.ring, n)

	return j, nil
}
