package rifle

import "base:runtime"
import "core:fmt"
import "core:sys/linux"
import "core:sys/linux/uring"

// TODO: Useful errors. Need to make RifleError into tagged union or smthn.
// TODO: Need to deal with cleanup for failures mid proc as we currently just return directly out in most cases. allocation failure etc.
// TODO: Handle timeouts
// TODO: Check read/write lenghts
// TODO: Handle when SQ is full
// TODO: Currently double iteration over file map during sync - implement something better
// TODO: Change to use REGISTER_FILE_ALLOC_RANGE and IORING_FILE_INDEX_ALLOC for managing open files
// TODO: custom formatter for fie paths

UringIO :: struct {
	ring:            uring.Ring,
	config:          UringConfig,
	file_index:      FileIndex,
	op_timeout:      linux.Time_Spec,
	dirfd:           linux.Fd,
	header_fd:       linux.Fd,
	header_dirty:    bool,
	paths:           [][len(DATA_PREFIX) + 20 + len(FILE_EXTENSION) + 1]u8,
	pending_syncs:   u32,
	sync_completion: IOCompletion,
	sync_pending:    bool,
}

UringConfig :: struct {
	params:    linux.IO_Uring_Params,
	num_files: u16, // MAX 1 << 12
	file_size: u64,
}

FileIndex :: struct {
	file_descriptors: []linux.Fd,
	slots:            []FileSlot,
	file_map:         map[i64]u16,
	slot_stack:       Stack(u16),
}

FileSlot :: struct {
	file_id: i64,
	state:   FileState,
}

FileState :: enum u8 {
	Empty,
	Opening,
	OpeningDirty,
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
	file_slot:  u16     | 12,
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
	HEADER,
	HEADER_SYNC,
}

new_uring_io :: proc(config: UringConfig, dirfd: linux.Fd) -> IO {
	uring_io := new(UringIO, context.allocator)
	uring_io.config = config
	uring_io.dirfd = dirfd
	io := IO {
		data         = uring_io,
		init         = uring_init,
		deinit       = uring_deinit,
		open         = uring_open,
		close        = uring_close,
		read_at      = uring_readat,
		write_at     = uring_writeat,
		write_header = uring_write_header,
		sync         = uring_sync,
		unlink       = uring_unlink,
		poll         = uring_poll,
	}

	return io
}

uring_init :: proc(ctx: rawptr, buffers: [][]u8) -> RifleError {
	io := cast(^UringIO)ctx
	iovecs, alloc_err := make([]Iovec, len(buffers), context.allocator)
	if alloc_err != nil {
		return .AllocatorError
	}
	for buffer, i in buffers {
		iovecs[i] = {raw_data(buffer), uintptr(len(buffer))}
	}
	success := false
	defer delete(iovecs)
	io.op_timeout.time_sec = 60
	err := uring.init(&io.ring, &io.config.params)
	if err != nil {
		return .GenericError
	}
	defer if !success {
		uring.destroy(&io.ring)
	}
	{
		assert(.SUBMIT_STABLE in io.ring.features)
		assert(.SQPOLL not_in io.config.params.flags)
	}
	io.paths, alloc_err = make([][len(DATA_PREFIX) + 20 + len(FILE_EXTENSION) + 1]u8, len(io.ring.sq.sqes), context.allocator)
	if alloc_err != nil {
		return .AllocatorError
	}
	defer if !success {
		delete(io.paths)
	}

	errno1 := linux.io_uring_register(io.ring.fd, .REGISTER_BUFFERS, raw_data(iovecs), u32(len(iovecs)))
	if errno1 != .NONE {
		return .GenericError
	}

	io.file_index.file_descriptors, _ = make([]linux.Fd, io.config.num_files, context.allocator)
	io.file_index.slots, _ = make([]FileSlot, io.config.num_files, context.allocator)
	io.file_index.file_map, _ = make(map[i64]u16, int(io.config.num_files) * 2, context.allocator) // Leave room so it never grows.
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

	header_fd, header_err := linux.openat(io.dirfd, BASE_FILENAME, {.RDWR, .CLOEXEC}, {})
	if header_err != .NONE {
		return .FileOperationError
	}
	io.header_fd = header_fd
	success = true
	return nil
}

uring_deinit :: proc(ctx: rawptr) -> RifleError {
	io := cast(^UringIO)ctx

	err := linux.io_uring_register(io.ring.fd, linux.IO_Uring_Register_Opcode.UNREGISTER_BUFFERS, nil, 0)
	uring.destroy(&io.ring)
	header_err := linux.close(io.header_fd)

	_ = delete(io.file_index.file_descriptors)
	_ = delete(io.file_index.slots)
	_ = delete(io.file_index.file_map)
	stack_deinit(&io.file_index.slot_stack)
	_ = delete(io.paths)
	_ = free(io)

	if err != .NONE || header_err != .NONE {
		return .GenericError
	}
	return nil
}

uring_open :: proc(ctx: rawptr, user_data: IOUserData, file_index: i64) -> RifleError {
	io := cast(^UringIO)ctx
	ud := cast(UringUserData)user_data

	check_sqe_space(&io.ring, 3) or_return

	file_slot, registered := register_file(&io.file_index, file_index)
	if !registered {
		return .GenericError
	}
	ud.file_slot = file_slot

	ud.op = .OPEN
	open_sqe, open_ok := uring.openat(
		&io.ring,
		cast(u64)ud,
		io.dirfd,
		uring_file_path(io, file_index),
		{.IRUSR, .IWUSR, .IRGRP, .IWGRP, .IROTH, .IWOTH},
		{.CREAT, .DIRECT, .RDWR},
		cast(u32)file_slot + 1,
	)
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

	io.file_index.slots[file_slot].state = .Opening

	return nil
}

uring_close :: proc(ctx: rawptr, user_data: IOUserData, file_index: i64) -> RifleError {
	io := cast(^UringIO)ctx
	ud := cast(UringUserData)user_data

	file_slot, exists := get_file_slot(&io.file_index, file_index)
	if !exists {
		return .GenericError
	}
	{
		assert(io.file_index.slots[file_slot].state == .Open, "caller must sync the file and wait for completion before closing")
	}
	ud.file_slot = file_slot

	ud.op = .CLOSE
	sqe, ok := uring.close(&io.ring, cast(u64)ud, 0, cast(u32)file_slot + 1)
	if !ok {
		return .GenericError
	}

	// Drain to close after any other ops on this file
	sqe.flags |= {.IO_LINK, .IO_DRAIN}

	link_timeout(&io.ring, ud, &io.op_timeout, {}) or_return

	io.file_index.slots[file_slot].state = .Closing

	return nil
}

uring_readat :: proc(ctx: rawptr, user_data: IOUserData, buffer: []u8, offset: u64, file_index: i64) -> RifleError {
	io := cast(^UringIO)ctx
	ud := cast(UringUserData)user_data

	file_slot, exists := get_file_slot(&io.file_index, file_index)
	{
		assert(!exists || io.file_index.slots[file_slot].state != .Closing, "cannot read from a closing file")
	}
	if exists && (io.file_index.slots[file_slot].state == .Opening || io.file_index.slots[file_slot].state == .OpeningDirty) {
		return .FileNotReady
	}
	if exists {
		check_sqe_space(&io.ring, 2) or_return
	}

	if !exists {
		check_sqe_space(&io.ring, 4) or_return
		registered: bool
		file_slot, registered = register_file(&io.file_index, file_index)
		if !registered {
			return .GenericError
		}
		ud.file_slot = file_slot
		ud.op = .OPEN
		open_sqe, open_ok := uring.openat(&io.ring, cast(u64)ud, io.dirfd, uring_file_path(io, file_index), {}, {.DIRECT, .RDWR}, cast(u32)file_slot + 1)
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
		io.file_index.slots[file_slot].state = .Opening
	}

	ud.file_slot = file_slot
	ud.op = .READ
	sqe, ok := read_fixed(&io.ring, cast(u64)ud, cast(linux.Fd)file_slot, buffer, offset, 0)
	if !ok {
		return .GenericError
	}
	sqe.flags |= {.IO_LINK, .FIXED_FILE}

	link_timeout(&io.ring, ud, &io.op_timeout, {}) or_return

	return nil
}

uring_writeat :: proc(ctx: rawptr, user_data: IOUserData, buffer: []u8, offset: u64, file_index: i64) -> RifleError {
	io := cast(^UringIO)ctx
	ud := cast(UringUserData)user_data

	file_slot, exists := get_file_slot(&io.file_index, file_index)
	{
		assert(!exists || io.file_index.slots[file_slot].state != .Closing, "cannot write to a closing file")
	}
	if exists && (io.file_index.slots[file_slot].state == .Opening || io.file_index.slots[file_slot].state == .OpeningDirty) {
		return .FileNotReady
	}

	if exists {
		check_sqe_space(&io.ring, 2) or_return
	}

	if !exists {
		check_sqe_space(&io.ring, 4) or_return
		registered: bool
		file_slot, registered = register_file(&io.file_index, file_index)
		if !registered {
			return .GenericError
		}
		ud.file_slot = file_slot
		ud.op = .OPEN
		open_sqe, open_ok := uring.openat(
			&io.ring,
			cast(u64)ud,
			io.dirfd,
			uring_file_path(io, file_index),
			{.IRUSR, .IWUSR, .IRGRP, .IWGRP, .IROTH, .IWOTH}, //TODO: double check flags
			{.DIRECT, .RDWR, .CREAT},
			cast(u32)file_slot + 1,
		)
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
		io.file_index.slots[file_slot].state = .Opening
	}

	ud.file_slot = file_slot
	ud.op = .WRITE
	sqe, ok := write_fixed(&io.ring, cast(u64)ud, cast(linux.Fd)file_slot, buffer, offset, 1)
	if !ok {
		return .GenericError
	}
	sqe.flags |= {.IO_LINK, .FIXED_FILE}
	io.file_index.slots[file_slot].state = exists ? .Dirty : .OpeningDirty
	link_timeout(&io.ring, ud, &io.op_timeout, {}) or_return

	return nil
}

uring_write_header :: proc(ctx: rawptr, user_data: IOUserData, buffer: []u8) -> RifleError {
	io := cast(^UringIO)ctx
	ud := cast(UringUserData)user_data

	check_sqe_space(&io.ring, 2) or_return

	ud.op = .HEADER
	sqe, ok := write_fixed(&io.ring, cast(u64)ud, io.header_fd, buffer, BASE_FILE_PREFIX_SIZE - 2 * size_of(i64), 1)
	if !ok {
		return .GenericError
	}
	sqe.flags |= {.IO_LINK}
	link_timeout(&io.ring, ud, &io.op_timeout, {}) or_return
	io.header_dirty = true

	return nil
}

uring_sync :: proc(ctx: rawptr, user_data: IOUserData) -> RifleError {
	io := cast(^UringIO)ctx
	ud := cast(UringUserData)user_data

	{
		assert(!io.sync_pending, "caller must wait for the previous sync batch")
	}
	dirty_files := 0
	for _, slot in io.file_index.file_map {
		if io.file_index.slots[slot].state == .Dirty || io.file_index.slots[slot].state == .OpeningDirty {
			dirty_files += 1
		}
	}
	check_sqe_space(&io.ring, 2 * (dirty_files + int(io.header_dirty))) or_return

	ud.op = .SYNC
	io.sync_completion = {
		user_data = cast(IOUserData)ud,
	}
	io.sync_completion.user_data.reserved = 0
	io.sync_pending = true
	flags := linux.IO_Uring_Fsync_Flags{.DATASYNC}
	first := true
	for _, slot in io.file_index.file_map { 	// Maybe change way to get all slots
		if io.file_index.slots[slot].state == .Dirty || io.file_index.slots[slot].state == .OpeningDirty {
			ud.file_slot = slot
			sqe, ok := uring.fsync(&io.ring, cast(u64)ud, cast(linux.Fd)slot, flags)
			if !ok {
				return .GenericError
			}
			if first {
				sqe.flags |= {.IO_DRAIN}
				first = false
			}
			sqe.flags |= {.FIXED_FILE, .IO_LINK}

			link_timeout(&io.ring, ud, &io.op_timeout, {}) or_return
			io.file_index.slots[slot].state = .Flushing
			io.pending_syncs += 1
		}
	}

	if io.header_dirty {
		ud.op = .HEADER_SYNC
		sqe, ok := uring.fsync(&io.ring, cast(u64)ud, io.header_fd, flags)
		if !ok {
			return .GenericError
		}
		if first {
			sqe.flags |= {.IO_DRAIN}
		}
		sqe.flags |= {.IO_LINK}
		link_timeout(&io.ring, ud, &io.op_timeout, {}) or_return
		io.header_dirty = false
		io.pending_syncs += 1
	}

	return nil
}

uring_unlink :: proc(ctx: rawptr, user_data: IOUserData, file_index: i64) -> RifleError {
	io := cast(^UringIO)ctx
	ud := cast(UringUserData)user_data

	check_sqe_space(&io.ring, 2) or_return

	ud.op = .DELETE
	sqe, ok := unlinkat(&io.ring, cast(u64)ud, io.dirfd, uring_file_path(io, file_index), {})
	if !ok {
		return .GenericError
	}
	sqe.flags |= {.IO_LINK}

	link_timeout(&io.ring, ud, &io.op_timeout, {}) or_return

	return nil
}

uring_poll :: proc(ctx: rawptr, completions: []IOCompletion) -> (u32, RifleError) {
	io := cast(^UringIO)ctx

	for uring.sq_ready(&io.ring) > 0 {
		submitted, err := uring.submit(&io.ring, 0)
		if err != .NONE || submitted == 0 {
			return 0, .GenericError
		}
	}

	if uring.cq_ring_needs_flush(&io.ring) {
		_, err := linux.io_uring_enter(io.ring.fd, 0, 0, {.GETEVENTS}, nil) // TODO: swap to uring method
		if err != .NONE {
			return 0, .GenericError
		}
	}

	n := uring.cq_ready(&io.ring)
	head := io.ring.cq.head^
	mask := io.ring.cq.mask
	j: u32 = 0
	i: u32 = 0
	for ; i < n && cast(int)j < len(completions); i += 1 {
		cqe := &io.ring.cq.cqes[(head + i) & mask]
		ud := cast(UringUserData)cqe.user_data

		completion := IOCompletion {
			user_data = cast(IOUserData)ud,
			res       = cqe.res,
		}

		completion.user_data.reserved = 0

		slot := ud.file_slot

		// Internal completions do not need file slot metadata.
		if ud.op != .OPEN && ud.op != .TIMEOUT && ud.op != .DELETE && ud.op != .HEADER && ud.op != .HEADER_SYNC {
			{
				assert(int(slot) < len(io.file_index.slots))
			}
		}

		switch ud.op {
		case .OPEN:
			if cqe.res != 0 {
				remove_file(&io.file_index, slot)
			}
		case .CLOSE:
			{
				assert(io.file_index.slots[slot].state == .Closing)
			}
			if cqe.res == 0 {
				remove_file(&io.file_index, slot)
			}
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
		case .HEADER:
			completion.user_data.op = .HEADER
			completions[j] = completion
			j += 1
		case .SYNC:
			{
				assert(io.pending_syncs > 0)
			}
			io.pending_syncs -= 1
			if cqe.res < 0 {
				io.sync_completion.res = cqe.res
			}
			if io.file_index.slots[slot].state == .Flushing {
				io.file_index.slots[slot].state = (cqe.res == 0) ? .Open : .Dirty
			}
		case .HEADER_SYNC:
			{
				assert(io.pending_syncs > 0)
			}
			io.pending_syncs -= 1
			if cqe.res < 0 {
				io.sync_completion.res = cqe.res
				io.header_dirty = true
			}
		case .DELETE:
			completion.user_data.op = .DELETE
			completions[j] = completion
			j += 1
		case .ALLOCATE:
			if cqe.res == 0 {
				#partial switch io.file_index.slots[slot].state {
				case .Opening:
					io.file_index.slots[slot].state = .Open
				case .OpeningDirty:
					io.file_index.slots[slot].state = .Dirty
				}
			}
			completion.user_data.op = .OPEN
			completions[j] = completion
			j += 1
		case .TIMEOUT:
		// Eventually do something here
		}
	}

	uring.cq_advance(&io.ring, i)
	if io.sync_pending && io.pending_syncs == 0 && cast(int)j < len(completions) {
		completions[j] = io.sync_completion
		j += 1
		io.sync_pending = false
	}

	return j, nil
}

// Needs SUBMIT_STABLE and no SQPOLL
@(private)
uring_file_path :: proc(io: ^UringIO, file_index: i64) -> cstring {
	buffer := io.paths[io.ring.sq.sqe_tail & io.ring.sq.mask][:]
	path := fmt.bprintf(buffer[:len(buffer) - 1], "%s%020d%s", DATA_PREFIX, file_index, FILE_EXTENSION)
	buffer[len(path)] = 0
	return cstring(raw_data(buffer))
}


get_file_slot :: proc(files: ^FileIndex, file_index: i64) -> (u16, bool) {
	return files.file_map[file_index]
}

register_file :: proc(files: ^FileIndex, file_index: i64) -> (u16, bool) {
	if _, exists := files.file_map[file_index]; exists {
		return 0, false
	}

	slot, ok := stack_pop(&files.slot_stack)
	if !ok {
		return 0, false
	}

	{
		assert(u32(slot) < (1 << 12))
		assert(files.slots[slot].state == .Empty)
	}

	files.file_map[file_index] = slot
	files.slots[slot] = {
		file_id = file_index,
	}

	return slot, true
}

remove_file :: proc(files: ^FileIndex, slot: u16) {
	entry := &files.slots[slot]
	file_id := entry.file_id

	{
		when !ODIN_DISABLE_ASSERT {
			mapped_slot, exists := files.file_map[file_id]
			assert(exists && mapped_slot == slot)
		}
	}
	_, _ = delete_key(&files.file_map, file_id)
	entry^ = {}

	returned := stack_push(&files.slot_stack, slot)
	{
		assert(returned)
	}
}

check_sqe_space :: proc(ring: ^uring.Ring, n: int) -> RifleError {
	if n > len(ring.sq.sqes) - int(uring.sq_ready(ring)) {
		return .GenericError
	}
	return nil
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

uring_io_arena_size :: proc(num_files: u16, num_entries, num_buffers: int) -> i64 {
	map_capacity := uintptr(1) << runtime.MAP_MIN_LOG2_CAPACITY
	for map_capacity < uintptr(num_files) * 2 {
		map_capacity *= 2
	}
	map_size := i64(runtime.map_total_allocation_size(map_capacity, runtime.map_info(map[i64]u16)))
	return(
		size_of(UringIO) +
		align_of(UringIO) +
		i64(num_buffers) * size_of(Iovec) +
		align_of(Iovec) +
		i64(num_entries) * (len(DATA_PREFIX) + 20 + len(FILE_EXTENSION) + 1) +
		1 +
		i64(num_files) * size_of(linux.Fd) +
		align_of(linux.Fd) +
		i64(num_files) * size_of(FileSlot) +
		align_of(FileSlot) +
		map_size +
		runtime.MAP_CACHE_LINE_SIZE +
		i64(num_files) * size_of(u16) +
		align_of(u16) \
	)
}
