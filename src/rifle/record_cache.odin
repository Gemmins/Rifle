package rifle

import "core:mem"
import "core:sync"
import "core:sys/linux"
import "core:sys/posix"

COMPLETION_QUEUE_COUNT :: 128
SET_ASSOC :: 4 // LRU impl requires 4

RecordCache :: struct {
	ring_data:            []u8,
	ring_mask:            i64,
	header_data:          []u8,
	header_in_progress:   bool,
	commit_ring:          []paddedValue(i64),
	writes:               []RecordCacheWrite,
	write_head:           i64,
	write_count:          i64,
	writing_byte_index:   i64,
	persisted_byte_index: i64,
	write_failed:         bool,
	pages:                []RecordCachePage,
	sets:                 []RecordCacheSet(SET_ASSOC),
	page_size:            i64,
	read_chunk_size:      i64,
	record_size:          i64,
	file_size:            i64,
	io:                   IO,
	unlinks:              []RecordCacheUnlink,
	unlink_index:         i64, // Next file to assign to an unlink slot.
	unlink_retry:         bool,
	polling:              u32,
	sync_pending:         bool,
	sync_in_progress:     bool,
	sync_index:           i64,
	visible_index:        ^i64,
	persisted_index:      ^i64,
	durable_index:        ^i64,
	dropped_index:        ^i64,
}

RecordCacheWrite :: struct {
	start, end: i64,
	result:     i32,
	complete:   bool,
}

RecordCacheUnlink :: struct {
	file_id: i64,
	pending: bool,
}

RecordCachePage :: struct {
	file_id:   i64,
	data:      []u8,
	index:     i64,
	ref_count: i64,
	state:     RecordCachePageState,
}

RecordCachePageState :: enum u32 {
	Empty,
	Read_Pending,
	Loading,
	Clean,
}

RecordCacheSet :: struct($Assoc: i64) {
	pages: []RecordCachePage,
	lock:  u32,
	lru:   lru,
}

new_record_cache :: proc() -> Cache {
	return {data = new(RecordCache, context.allocator), init = rc_init, deinit = rc_deinit, read = rc_read, write = rc_write, poll = rc_poll, sync = rc_sync}
}

rc_init :: proc(
	ctx: rawptr,
	ring_capcity: i64,
	page_capcity: i64, // Could change this to count idk
	page_size: i64,
	commit_ring_size: i64,
	io: IO,
	file_size: i64,
	record_size: i64,
	visible_index: ^i64,
	persisted_index: ^i64,
	durable_index: ^i64,
	dropped_index: ^i64,
	read_chunk_size: i64 = 0, // Pages per read chunk; 0 defaults to the number of sets.
) -> RifleError {
	cache := cast(^RecordCache)ctx
	sys_page_size := i64(posix.sysconf(._PAGE_SIZE))
	{
		assert(cache != nil)
		assert(sys_page_size > 0)
		assert(ring_capcity > 0 && ring_capcity <= 1 << 36)
		assert(ring_capcity & (ring_capcity - 1) == 0)
		assert(ring_capcity % sys_page_size == 0)
		assert(commit_ring_size > 0)
		assert(commit_ring_size & (commit_ring_size - 1) == 0)
		assert(page_size >= 4096 && page_size % sys_page_size == 0)
		assert(page_size & (page_size - 1) == 0)
		assert(ring_capcity >= page_size)
		assert(page_capcity > 0 && page_capcity % page_size == 0)
		assert(file_size > 0 && file_size % page_size == 0)
		assert(record_size > 0)
		assert(visible_index != nil)
		assert(persisted_index != nil)
		assert(durable_index != nil)
		assert(dropped_index != nil)
		assert(io.init != nil)
		assert(context.allocator.procedure == file_backed_arena_proc)
		assert(context.allocator.data != nil)
	}
	arena := cast(^FileBackedArena)context.allocator.data
	{
		assert(arena.allocator_tail % sys_page_size == 0)
	}
	num_pages := page_capcity / page_size
	chunk_size := read_chunk_size
	if chunk_size == 0 {
		chunk_size = num_pages / SET_ASSOC
	}
	{
		assert(num_pages % SET_ASSOC == 0)
		assert(chunk_size > 0 && chunk_size <= num_pages / SET_ASSOC)
	}

	header_size := i64(2 * size_of(i64))
	ring_backing, err := alloc_from_end(arena, 2 * ring_capcity + header_size)
	if err != nil {
		return .AllocatorError
	}

	ring_data := ring_backing[header_size:]
	ring_offset := arena.allocator_tail + header_size
	_, mmap_err := linux.mmap(
		uintptr(raw_data(ring_data)) + uintptr(ring_capcity),
		uint(ring_capcity),
		{.READ, .WRITE},
		{.SHARED, .FIXED},
		arena.file,
		ring_offset,
	)
	if mmap_err != .NONE {
		arena.allocator_tail += 2 * ring_capcity + header_size
		return .FileOperationError
	}

	backing, backing_err := make_aligned([]u8, page_capcity + num_pages * size_of(RecordCachePage), int(sys_page_size), context.allocator)
	if backing_err != nil {
		return .AllocatorError
	}
	page_data := backing[:page_capcity]
	cache.pages = mem.slice_data_cast([]RecordCachePage, backing[page_capcity:])
	for &page, i in cache.pages {
		page = RecordCachePage {
			index = -1,
			data  = page_data[i64(i) * page_size:(i64(i) + 1) * page_size],
		}
	}

	cache.sets, err = make([]RecordCacheSet(SET_ASSOC), num_pages / SET_ASSOC, context.allocator)
	if err != nil {
		return .AllocatorError
	}
	for &set, i in cache.sets {
		set = RecordCacheSet(SET_ASSOC) {
			pages = cache.pages[i * SET_ASSOC:(i + 1) * SET_ASSOC],
			lru   = lru_new(),
		}
	}

	cache.commit_ring, err = make([]paddedValue(i64), commit_ring_size, context.allocator)
	if err != nil {
		return .AllocatorError
	}
	for &entry in cache.commit_ring {
		sync.atomic_store(&entry.value, -1)
	}

	cache.page_size = page_size
	cache.read_chunk_size = chunk_size
	cache.ring_data = ring_data
	cache.header_data = ring_backing[:header_size]
	cache.ring_mask = ring_capcity - 1
	cache.file_size = file_size
	cache.record_size = record_size
	cache.visible_index = visible_index
	cache.persisted_index = persisted_index
	cache.durable_index = durable_index
	cache.dropped_index = dropped_index
	cache.persisted_byte_index = sync.atomic_load(persisted_index) * record_size
	cache.writing_byte_index = cache.persisted_byte_index

	{
		assert(COMPLETION_QUEUE_COUNT > 0 && COMPLETION_QUEUE_COUNT & (COMPLETION_QUEUE_COUNT - 1) == 0)
	}
	cache.writes, err = make([]RecordCacheWrite, COMPLETION_QUEUE_COUNT, context.allocator)
	if err != nil {
		return .AllocatorError
	}

	cache.unlinks, err = make([]RecordCacheUnlink, 8, context.allocator)
	if err != nil {
		return .AllocatorError
	}
	for &unlink in cache.unlinks {
		unlink.file_id = -1
	}
	cache.io = io

	cache.io.init(cache.io.data, [][]u8{page_data, ring_backing}) or_return

	return nil
}

rc_deinit :: proc(ctx: rawptr) -> RifleError {
	cache := cast(^RecordCache)ctx
	io_err := cache.io.deinit(cache.io.data)
	ring_capacity := cache.ring_mask + 1
	unmap_err := linux.munmap(&cache.ring_data[ring_capacity], uint(ring_capacity))
	if io_err != nil {
		return io_err
	}
	if unmap_err != .NONE {
		return .FileOperationError
	}
	return nil
}

rc_read :: proc(ctx: rawptr, data: []u8, start: i64, count: i64) -> RifleError {
	cache := cast(^RecordCache)ctx
	visible := sync.atomic_load_explicit(cache.visible_index, .Acquire)
	{
		assert(start >= 0 && count >= 0)
		assert(cache.record_size > 0)
		assert(start + count <= visible)
		assert(i64(len(data)) >= count * cache.record_size)
	}
	if count == 0 {
		return nil
	}

	end := start + count
	page_end := clamp(sync.atomic_load_explicit(cache.persisted_index, .Acquire), start, end)
	if page_end < end {
		ring_start := page_end
		byte_count := (end - ring_start) * cache.record_size
		offset := (ring_start * cache.record_size) & cache.ring_mask
		dst_start := (ring_start - start) * cache.record_size
		copy(data[dst_start:dst_start + byte_count], cache.ring_data[offset:offset + byte_count])
		sync.atomic_thread_fence(.Acquire)
		page_end = max(page_end, min(end, sync.atomic_load_explicit(cache.persisted_index, .Relaxed)))
	}
	if page_end == start {
		return nil
	}

	read_start := start * cache.record_size
	read_end := page_end * cache.record_size
	end_page := (read_end - 1) / cache.page_size + 1
	for first := read_start / cache.page_size; first < end_page; first += cache.read_chunk_size {
		last := min(end_page, first + cache.read_chunk_size)
		pinned_end := first
		defer {
			for index := first; index < pinned_end; index += 1 {
				set := rc_lock_set(cache, index % i64(len(cache.sets)))
				for &page in set.pages {
					if page.index != index {
						continue
					}
					{
						assert(page.ref_count > 0)
					}
					page.ref_count -= 1
					break
				}
				rc_unlock_set(set)
			}
		}
		for index := first; index < last; {
			set := rc_lock_set(cache, index % i64(len(cache.sets)))
			page, slot := rc_find_or_allocate_page(cache, set, index)
			if page != nil {
				page.ref_count += 1
				set.lru = lru_update(set.lru, slot)
				index += 1
				pinned_end = index
			}
			rc_unlock_set(set)
			if page == nil {
				_ = rc_poll(cache) or_return
			}
		}
		for index := first; index < last; {
			set := rc_lock_set(cache, index % i64(len(cache.sets)))
			waiting := false
			for &page in set.pages {
				if page.index != index {
					continue
				}
				{
					assert(page.ref_count > 0)
				}
				if page.state != .Clean {
					waiting = true
					break
				}
				page_start := index * cache.page_size
				src_start := max(read_start - page_start, 0)
				src_end := min(read_end - page_start, cache.page_size)
				dst_start := page_start + src_start - read_start
				copy(data[dst_start:dst_start + src_end - src_start], page.data[src_start:src_end])
				break
			}
			rc_unlock_set(set)
			if waiting {
				_ = rc_poll(cache) or_return
				continue
			}
			index += 1
		}
	}
	return nil
}

rc_write :: proc(ctx: rawptr, data: []u8, start: i64, count: i64) -> RifleError {
	cache := cast(^RecordCache)ctx
	ring_capacity := cache.ring_mask + 1
	commit_mask := u64(len(cache.commit_ring) - 1)
	{
		assert(start >= 0 && count >= 0)
		assert(cache.record_size > 0 && cache.record_size <= ring_capacity)
		assert(i64(len(data)) >= count * cache.record_size)
	}
	end := start + count
	for next := start; next < end; {
		persisted := sync.atomic_load_explicit(cache.persisted_index, .Acquire)
		available := max(0, ring_capacity / cache.record_size - (next - persisted))
		if available == 0 {
			_ = rc_poll(cache) or_return
			continue
		}

		chunk_count := min(end - next, available)
		chunk_end := next + chunk_count
		byte_count := chunk_count * cache.record_size
		ring_offset := (next * cache.record_size) & cache.ring_mask
		source_offset := (next - start) * cache.record_size
		copy(cache.ring_data[ring_offset:ring_offset + byte_count], data[source_offset:source_offset + byte_count])

		for next - sync.atomic_load_explicit(cache.visible_index, .Acquire) >= i64(len(cache.commit_ring)) {
			_ = rc_poll(cache) or_return
		}
		sync.atomic_store_explicit(&cache.commit_ring[u64(next) & commit_mask].value, chunk_end, .Release)

		for {
			head := sync.atomic_load_explicit(cache.visible_index, .Acquire)
			completed_end := sync.atomic_load_explicit(&cache.commit_ring[u64(head) & commit_mask].value, .Acquire)
			if completed_end <= head {
				break
			}
			sync.atomic_compare_exchange_strong(cache.visible_index, head, completed_end)
		}
		next = chunk_end
	}
	return nil
}

rc_poll :: proc(ctx: rawptr) -> (polled: bool, err: RifleError) {
	cache := cast(^RecordCache)ctx
	if _, locked := sync.atomic_compare_exchange_strong(&cache.polling, 0, 1); !locked {
		return false, nil
	}
	defer sync.atomic_store(&cache.polling, 0)
	polled = true


	// Handle indexes after dropped advances
	dropped := sync.atomic_load_explicit(cache.dropped_index, .Acquire)
	dropped_bytes := dropped * cache.record_size

	cache.persisted_byte_index = max(cache.persisted_byte_index, dropped_bytes - dropped_bytes % cache.page_size)
	cache.writing_byte_index = max(cache.writing_byte_index, cache.persisted_byte_index)
	if dropped > sync.atomic_load(cache.persisted_index) {
		sync.atomic_store_explicit(cache.persisted_index, dropped, .Release)
	}
	if dropped > sync.atomic_load(cache.durable_index) {
		sync.atomic_store_explicit(cache.durable_index, dropped, .Release)
	}

	// Issue reads for pages
	for _, set_index in cache.sets {
		set := rc_lock_set(cache, i64(set_index))
		for &page, slot in set.pages {
			if page.state != .Read_Pending || page.ref_count == 0 {
				continue
			}
			read_err := cache.io.read_at(
				cache.io.data,
				{op = .READ, page_index = u32(set_index * SET_ASSOC + slot)},
				page.data,
				u64(page.index * cache.page_size % cache.file_size),
				page.file_id,
			)
			if read_err == nil {
				page.state = .Loading
			} else if read_err != .FileNotReady {
				err = read_err
			}
		}
		rc_unlock_set(set)
	}

	// Write as many pages as possible from the ring buffer
	visible := sync.atomic_load_explicit(cache.visible_index, .Acquire)
	visible_bytes := visible * cache.record_size
	aligned_end := visible_bytes - visible_bytes % cache.page_size
	start := cache.writing_byte_index
	max_bytes := i64(max(i32)) / cache.page_size * cache.page_size
	end := start + min(aligned_end - start, cache.file_size - start % cache.file_size, max_bytes)

	if start < end && cache.write_count < i64(len(cache.writes)) && !cache.write_failed {
		file_id := start / cache.file_size

		ring_offset := start & cache.ring_mask
		slot := (cache.write_head + cache.write_count) & (i64(len(cache.writes)) - 1)
		write_err := cache.io.write_at(
			cache.io.data,
			{op = .WRITE, page_index = u32(slot)},
			cache.ring_data[ring_offset:ring_offset + end - start],
			u64(start % cache.file_size),
			file_id,
		)
		if write_err == nil {
			cache.writes[slot] = {
				start = start,
				end   = end,
			}
			cache.writing_byte_index = end
			cache.write_count += 1
		} else if write_err != .FileNotReady {
			err = write_err
		}
	}

	// Unlink files completely below the unlink index
	unlink_end := dropped_bytes / cache.file_size
	if err == nil && (cache.unlink_index < unlink_end || cache.unlink_retry) {
		cache.unlink_retry = false
		for &unlink, slot in cache.unlinks {
			if unlink.pending {
				continue
			}
			if unlink.file_id == -1 {
				if cache.unlink_index >= unlink_end {
					continue
				}
				unlink.file_id = cache.unlink_index
				cache.unlink_index += 1
			}
			unlink_err := cache.io.unlink(cache.io.data, {op = .DELETE, page_index = u32(slot)}, unlink.file_id)
			if unlink_err != nil {
				cache.unlink_retry = true
				if unlink_err != .FileNotReady {
					err = unlink_err
				}
				break
			}
			unlink.pending = true
		}
	}

	// Update the values stored in the header file
	if err == nil && !cache.header_in_progress {
		header := mem.slice_data_cast([]i64le, cache.header_data)
		header[0] = i64le(sync.atomic_load_explicit(cache.persisted_index, .Acquire))
		header[1] = i64le(dropped)
		header_err := cache.io.write_header(cache.io.data, {op = .HEADER}, cache.header_data)
		if header_err == nil {
			cache.header_in_progress = true
		} else if header_err != .FileNotReady {
			err = header_err
		}
	}

	// Fsync all visible values in the cache
	// TODO: partial page writes
	if err == nil && !cache.sync_in_progress && sync.atomic_exchange(&cache.sync_pending, false) {
		visible = sync.atomic_load_explicit(cache.visible_index, .Acquire)
		visible_bytes = visible * cache.record_size
		aligned_end = visible_bytes - visible_bytes % cache.page_size
		switch {
		case visible > sync.atomic_load(cache.durable_index) && cache.writing_byte_index < visible_bytes:
			sync.atomic_store(&cache.sync_pending, true)
			if visible_bytes != aligned_end && cache.writing_byte_index == aligned_end {
				err = rc_write_partial_page(cache, visible)
			}
		case:
			err = cache.io.sync(cache.io.data, {op = .SYNC})
			if err != nil {
				sync.atomic_store(&cache.sync_pending, true)
			} else {
				cache.sync_index = visible
				cache.sync_in_progress = true
			}
		}
	}

	// Submit operations and process completions
	completions: [COMPLETION_QUEUE_COUNT]IOCompletion
	n, poll_err := cache.io.poll(cache.io.data, completions[:])
	if poll_err != nil {
		return polled, poll_err
	}
	synced := false
	for completion in completions[:n] {
		switch completion.user_data.op {
		case .WRITE:
			write := &cache.writes[completion.user_data.page_index]
			{
				assert(!write.complete)
				assert(i64(completion.res) <= write.end - write.start)
			}
			write.result = completion.res
			write.complete = true
			if i64(write.result) != write.end - write.start && write.end > dropped_bytes {
				cache.write_failed = true
				err = .FileOperationError
			}
		case .HEADER:
			cache.header_in_progress = false
			if completion.res != i32(len(cache.header_data)) {
				err = .FileOperationError
			}
		case .SYNC:
			cache.sync_in_progress = false
			if completion.res == 0 {
				synced = true
			} else {
				sync.atomic_store(&cache.sync_pending, true)
				err = .FileOperationError
			}
		case .OPEN:
			if completion.res < 0 {
				err = .FileOperationError
			}
		case .DELETE:
			unlink := &cache.unlinks[completion.user_data.page_index]
			unlink.pending = false
			if completion.res == 0 || completion.res == -i32(linux.Errno.ENOENT) {
				unlink.file_id = -1
			} else {
				cache.unlink_retry = true
				err = .FileOperationError
			}
		case .READ:
			page := &cache.pages[completion.user_data.page_index]
			set := rc_lock_set(cache, i64(completion.user_data.page_index) / SET_ASSOC)
			{
				assert(page.state == .Loading)
			}
			if i64(completion.res) == cache.page_size {
				page.state = .Clean
			} else {
				page.state = .Read_Pending
				err = .FileOperationError
			}
			rc_unlock_set(set)
		case .CLOSE:
		}
	}
	persisted := cache.persisted_byte_index

	// Retire completed writes and advance the persisted prefix.
	for cache.write_count > 0 {
		write := &cache.writes[cache.write_head]
		if !write.complete {
			break
		}
		if write.start <= persisted && write.result > 0 {
			written := i64(write.result)
			written -= written % cache.page_size
			persisted = max(persisted, write.start + written)
		}
		cache.write_head = (cache.write_head + 1) & (i64(len(cache.writes)) - 1)
		cache.write_count -= 1
	}
	if persisted != cache.persisted_byte_index {
		cache.persisted_byte_index = persisted
		sync.atomic_store_explicit(cache.persisted_index, max(dropped, persisted / cache.record_size), .Release)
	}

	// Advance durability through the prefix covered by the completed sync.
	if synced {
		durable := min(cache.sync_index, sync.atomic_load(cache.persisted_index))
		sync.atomic_store_explicit(cache.durable_index, max(sync.atomic_load(cache.durable_index), durable), .Release)
		if durable < cache.sync_index {
			sync.atomic_store(&cache.sync_pending, true)
		}
	}

	// Retry from the persisted prefix once failed writes have drained.
	if cache.write_failed && cache.write_count == 0 && !cache.sync_in_progress {
		cache.writing_byte_index = persisted
		cache.write_failed = false
	}
	return
}

@(private)
rc_write_partial_page :: proc(cache: ^RecordCache, target: i64) -> RifleError {
	return .UnimplementedError
}

rc_sync :: proc(ctx: rawptr) {
	cache := cast(^RecordCache)ctx
	sync.atomic_store(&cache.sync_pending, true)
}

@(private)
rc_find_or_allocate_page :: proc(cache: ^RecordCache, set: ^RecordCacheSet(SET_ASSOC), index: i64) -> (^RecordCachePage, u8) {
	for &page, slot in set.pages {
		if page.index == index {
			return &page, u8(slot)
		}
	}
	for slot in lru_get_order(set.lru) {
		page := &set.pages[slot]
		if page.ref_count != 0 || page.state == .Loading {
			continue
		}
		page.index = index
		page.file_id = index * cache.page_size / cache.file_size
		page.state = .Read_Pending
		return page, slot
	}
	return nil, 0
}

@(private)
rc_lock_set :: proc(cache: ^RecordCache, index: i64) -> ^RecordCacheSet(SET_ASSOC) {
	set := &cache.sets[index]
	for {
		if _, locked := sync.atomic_compare_exchange_strong(&set.lock, 0, 1); locked {
			return set
		}
	}
}

@(private)
rc_unlock_set :: proc(set: ^RecordCacheSet(SET_ASSOC)) {
	sync.atomic_store_explicit(&set.lock, 0, .Release)
}
