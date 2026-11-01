package rifle

import "base:intrinsics"
import "core:container/lru"
// import "core:fmt"
import "base:runtime"
import "core:mem"
import "core:mem/virtual"
import "core:nbio"
import "core:sync"
import "core:thread"

Log_old :: struct {
	arena:                virtual.Arena,
	base_path:            string,
	path_slice:           []u8,
	record_size:          i64,
	records_per_block:    i64,
	record_shift:         u64,
	blocks_per_file:      i64,
	block_shift:          u64,
	cache_size_in_blocks: i64,
	block_cache:          ^BlockCache,
	max_open_files:       i64,
	open_files:           ^lru.Cache(i64, FileInfo),
	io_loop:              ^nbio.Event_Loop,
	io_thread:            ^thread.Thread,
	loop_ready:           bool,
	loop_shutdown:        bool,
	commit_ring:          []i64, // TODO: Use paddedValues here
	commit_ring_mask:     u64,
	commit_index:         paddedValue(i64),
	write_index:          paddedValue(i64),
	tail_index:           paddedValue(i64),
	files_mu:             sync.Mutex, // TODO: Improve dealing with file handles
}

Block :: struct {
	// not figured out the header yet
	data:         []u8,
	index:        i64,
	loaded:       sync.Futex,
	record_count: i64,
}

FileInfo :: struct {
	readers: i64,
	index:   i64,
	handle:  nbio.Handle,
}

// Lifecycle

log_create :: proc(
	path: string,
	record_size, records_per_block, blocks_per_file, cache_size_in_blocks, max_open_files: i64,
	commit_ring_size: i64 = 1 << 16,
) -> (
	l: ^Log_old,
	err: RifleError,
) {
	arena_size := cache_size_in_blocks * (size_of(Block) + (record_size * records_per_block)) + (max_open_files * size_of(FileInfo)) // TODO: Better estimate, possible mlock()?

	error: runtime.Allocator_Error
	l, error = virtual.arena_growing_bootstrap_new(Log_old, "arena", cast(uint)arena_size)
	if error != nil {
		return l, .AllocatorError
	}

	context.allocator = virtual.arena_allocator(&l.arena)

	l.base_path = path
	// Cap covers <base_path>/data_<i64>.rfl; i64 max is 20 chars.
	l.path_slice = make([]u8, len(path) + len(PATH_SEPARATOR) + len(DATA_PREFIX) + 20 + len(FILE_EXTENSION))

	l.commit_ring = make([]i64, commit_ring_size * 8)
	runtime.memset(mem.raw_data(l.commit_ring), -1, len(l.commit_ring) * size_of(i64))
	l.commit_ring_mask = cast(u64)(commit_ring_size - 1)

	l.record_size = record_size

	if intrinsics.count_ones(cast(u64)records_per_block) != 1 || intrinsics.count_ones(cast(u64)blocks_per_file) != 1 {
		return nil, .InvalidArgError
	}

	l.records_per_block = records_per_block
	l.blocks_per_file = blocks_per_file

	ensure_base_directory_exists_or_create(path) or_return
	// write_base_file(l) or_return

	l.record_shift = intrinsics.count_trailing_zeros(cast(u64)records_per_block)
	l.block_shift = intrinsics.count_trailing_zeros(cast(u64)blocks_per_file)

	l.cache_size_in_blocks = cache_size_in_blocks

	l.block_cache, error = new(BlockCache)
	if error != nil {
		return l, .AllocatorError
	}

	error = block_cache_init(l.block_cache, l.cache_size_in_blocks, records_per_block * record_size)
	if error != nil {
		return l, .AllocatorError
	}

	l.io_thread = thread.create_and_start_with_data(l, io_thread_proc)
	for !sync.atomic_load(&l.loop_ready) {} 	// TODO: futex?

	l.max_open_files = max_open_files
	l.open_files = new(lru.Cache(i64, FileInfo))
	lru.init(l.open_files, cast(int)max_open_files)
	l.open_files.on_remove_user_data = l.io_loop
	l.open_files.on_remove = proc(key: i64, value: FileInfo, data: rawptr) {
		nbio.close(value.handle, close_cb, cast(^nbio.Event_Loop)data)
	}

	log_create_or_open_storage_file_blocking(l, 0) or_return

	return
}

io_thread_proc :: proc(log: rawptr) {
	l := cast(^Log_old)log
	nbio.acquire_thread_event_loop()
	defer nbio.release_thread_event_loop()

	l.io_loop = nbio.current_thread_event_loop()
	sync.atomic_store(&l.loop_ready, true)

	for !sync.atomic_load(&l.loop_shutdown) {
		nbio.tick(nbio.NO_TIMEOUT)
	}
}

close_cb :: proc(op: ^nbio.Operation) {
	return
}

log_destroy :: proc(l: ^Log_old) -> RifleError {
	if l == nil {
		return .InvalidArgError
	}

	sync.atomic_store(&l.loop_shutdown, true)
	nbio.wake_up(l.io_loop)
	thread.join(l.io_thread)
	thread.destroy(l.io_thread)

	arena := l.arena
	virtual.arena_destroy(&arena)
	return nil
	// TODO: flush un-commited blocks here
}

log_advance_tail :: proc(l: ^Log_old, index: i64) -> RifleError {
	sync.atomic_store(&l.tail_index.value, index) // TODO: memory model optimal?
	return nil
}

// Writes

log_append :: proc {
	log_append_single,
	log_append_many,
}

log_append_single :: proc(l: ^Log_old, data: []u8) -> (index: i64, err: RifleError) {
	return log_append_many(l, data, 1)
}

log_append_many :: proc(l: ^Log_old, data: []u8, count: i64) -> (index: i64, err: RifleError) {
	index = sync.atomic_add(&l.write_index.value, count)
	current_index := index
	end_index := index + count
	buf_pos: i64 = 0

	for current_index < end_index {
		block_index, offset := get_block_and_offset(l, current_index)

		within_block_pos := current_index & (l.records_per_block - 1)
		remaining_in_block := l.records_per_block - within_block_pos
		remaining_in_range := end_index - current_index
		to_copy := min(remaining_in_block, remaining_in_range)
		byte_count := to_copy * l.record_size

		// Take one reader ref per record written so the release_n on flush balances.
		block, _ := block_cache_get(l.block_cache, block_index, to_copy)
		sync.atomic_store(&block.loaded, 1)

		copy(block.data[offset:offset + byte_count], data[buf_pos:buf_pos + byte_count])

		for idx in current_index ..< current_index + to_copy {
			for idx - sync.atomic_load(&l.commit_index.value) >= cast(i64)l.commit_ring_mask { 	// wait until incomplete writes finish
				intrinsics.cpu_relax() // TODO: use something else?
			}
			sync.atomic_store(&l.commit_ring[(cast(u64)idx & l.commit_ring_mask) << 3], idx) // TODO: clean up magics
		}

		for {
			cur_idx := sync.atomic_load(&l.commit_index.value)
			pub := sync.atomic_load(&l.commit_ring[(cast(u64)cur_idx & l.commit_ring_mask) << 3])
			if pub != cur_idx do break
			sync.atomic_compare_exchange_strong(&l.commit_index.value, pub, pub + 1) or_break
		}

		// block full
		if sync.atomic_add(&block.record_count, to_copy) + to_copy == l.records_per_block {
			file_index, file_offset := get_file_index_and_offset(l, current_index)
			sync.lock(&l.files_mu)
			file, ok := lru.get(l.open_files, file_index)
			if !ok {
				file = log_create_or_open_storage_file_blocking(l, file_index) or_return
			}
			sync.unlock(&l.files_mu)

			nbio.write_poly3(file.handle, cast(int)file_offset, block.data, file_index, block_index, l, block_write_callback, l = l.io_loop)
		}

		current_index += to_copy
		buf_pos += byte_count
	}

	return
}

block_write_callback :: proc(op: ^nbio.Operation, file_index: i64, block_index: i64, l: ^Log_old) {
	block_cache_release_n(l.block_cache, block_index, l.records_per_block)
	return
}

// Reads

log_read_head :: proc(l: ^Log_old, buffer: []u8) -> RifleError {
	return log_read_index_single(l, buffer, sync.atomic_load(&l.commit_index.value) - 1)
}

log_read_tail :: proc(l: ^Log_old, buffer: []u8) -> RifleError {
	return log_read_index_single(l, buffer, sync.atomic_load(&l.tail_index.value))
}

log_read_index :: proc {
	log_read_index_single,
	log_read_many_index,
}

log_read_index_single :: proc(l: ^Log_old, buffer: []u8, index: i64) -> RifleError {
	return log_read_many_index(l, buffer, index, index + 1)
}

log_read_many_index :: proc(l: ^Log_old, buffer: []u8, start_index: i64, end_index: i64) -> RifleError {
	check_log_index_ok_range(l, start_index, end_index - 1) or_return
	current_index := start_index
	buf_pos: i64 = 0
	for current_index < end_index {
		block_index, offset := get_block_and_offset(l, current_index)

		block := read_block(l, block_index) or_return
		defer block_cache_release(l.block_cache, block_index)

		within_block_pos := current_index & (l.records_per_block - 1)
		remaining_in_block := l.records_per_block - within_block_pos
		remaining_in_range := end_index - current_index
		to_copy := min(remaining_in_block, remaining_in_range)
		byte_count := to_copy * l.record_size

		for sync.atomic_load(&block.loaded) == 0 {
			if !sync.wait_with_timeout(&block.loaded, 0, 1_000_000_000) {
				return .FileOperationError
			}
		}

		copy(buffer[buf_pos:buf_pos + byte_count], block.data[offset:offset + byte_count])
		current_index += to_copy
		buf_pos += byte_count
	}
	return nil
}

read_block :: proc(l: ^Log_old, block_index: i64) -> (block: ^Block, err: RifleError) {
	record_index := block_index << l.record_shift
	hit: bool
	block, hit = block_cache_get(l.block_cache, block_index)

	if !hit {
		file_index, file_offset := get_file_index_and_offset(l, record_index)
		sync.lock(&l.files_mu)
		file, ok := lru.get(l.open_files, file_index)
		if !ok {
			file = log_create_or_open_storage_file_blocking(l, file_index) or_return
		}
		sync.unlock(&l.files_mu)
		nbio.read_poly(file.handle, cast(int)file_offset, block.data, &block.loaded, file_read_callback, l = l.io_loop)
	}

	return block, nil
}

file_read_callback :: proc(op: ^nbio.Operation, loaded: ^sync.Futex) {
	sync.atomic_store(loaded, 1)
	sync.broadcast(loaded)
	return
}


log_head_index :: proc(l: ^Log_old) -> i64 {
	return sync.atomic_load(&l.commit_index.value)
}

log_tail_index :: proc(l: ^Log_old) -> i64 {
	return sync.atomic_load(&l.tail_index.value)
}
