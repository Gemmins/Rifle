package rifle

import "core:fmt"
import "core:mem"
import "core:strings"
import "core:sync"

import "core:log"

SET_ASSOC :: 4 // LRU impl requires 4
//TODO: divide page pinning into sections as to not lock up all/many pages on read/write
//TODO: handle file deletion responses
//TODO: just a boatload of handling errors i guess
//TODO: further consideration around behaviour of dropping files - ordering, reading from etc.
//TODO: rework - again! - going to move to a combined large ring buffer for writes and page cache for reads :)

PageCache :: struct {
	page_size:          i64,
	num_pages:          i64,
	pages:              []Page,
	pageData:           []u8,
	sets:               []Set(SET_ASSOC),
	pages_per_file:     i64,
	path_storage:       []u8,
	base_path:          string,
	io:                 IO,
	io_completions:     []IOCompletion,
	record_size:        i64,
	polling:            u32,
	sync_pending:       bool,
	sync_in_progress:   bool,
	sync_pending_index: i64,
	sync_index:         i64,
	durable_index:      ^i64,
}

Page :: struct {
	file_id:       i64,
	path:          cstring,
	path_buffer:   []u8,
	data:          []u8,
	index:         i64,
	written_bytes: i64,
	ref_count:     i64,
	state:         PageState,
}

PageState :: enum u32 {
	Empty, // Page contains no useable data
	Read_Pending, // Read from disk should be issued into this page
	Loading, // Data is being loaded from disk into this page
	Clean, // This page contains data which is also on disk
	Dirty, // This page contains data which has not yet been written to disk
	Flushing, // This page is being written to disk
}

Set :: struct($Assoc: i64) {
	pages: []Page,
	lock:  u32, //TODO: look at maybe separate reader/writer lock - most accesses are for reading
	lru:   lru,
}

new_page_cache :: proc() -> Cache {
	return {
		data = new(PageCache, context.allocator),
		init = cache_init,
		deinit = cache_deinit,
		read = cache_read,
		write = cache_write,
		poll = cache_poll,
		sync = cache_sync,
		drop = cache_drop,
	}
}

cache_init :: proc(
	ctx: rawptr,
	capacity_in_bytes: i64,
	page_size: i64 = 1 << 13,
	io: IO,
	base_path: string,
	file_size: i64,
	record_size: i64,
	durable_index: ^i64,
) -> RifleError {
	c := cast(^PageCache)ctx
	{
		assert(file_size > 0 && page_size > 0 && file_size % page_size == 0)
		assert(durable_index != nil)
	}
	c.durable_index = durable_index
	c.pages_per_file = file_size / page_size
	c.page_size = page_size
	num_pages := capacity_in_bytes / page_size
	c.num_pages = num_pages // Probs require some enforcement around this and assoc to ensure divisble

	backing := make_aligned([]u8, num_pages * (page_size + size_of(Page)), 1 << 12, context.allocator) // Alignment here will at some point be driven by system settings
	split_point := num_pages * page_size
	c.pages = mem.slice_data_cast([]Page, backing[split_point:])
	c.pageData = backing[:split_point]
	c.base_path = strings.clone(strings.trim_right(base_path, "/"))
	path_size := len(c.base_path) + 1 + len(DATA_PREFIX) + 20 + len(FILE_EXTENSION) + 1
	c.path_storage = make([]u8, num_pages * i64(path_size), context.allocator)
	for &v, i in c.pages {
		v.data = c.pageData[cast(i64)i * page_size:(cast(i64)i + 1) * page_size]
		sync.atomic_store_explicit(&v.index, -1, .Release)
		v.path_buffer = c.path_storage[i * path_size:(i + 1) * path_size]
		v.path = cstring(raw_data(v.path_buffer))
	}

	c.sets = make([]Set(SET_ASSOC), num_pages / SET_ASSOC)
	for &s, i in c.sets {
		s.pages = c.pages[(i * SET_ASSOC):(i * SET_ASSOC) + SET_ASSOC]
		s.lru = lru_new()
	}

	c.record_size = record_size

	c.io_completions = make([]IOCompletion, 128, context.allocator) //TODO: actual count
	c.io = io
	c.io.init(c.io.data, c.pageData)

	return nil
}

cache_deinit :: proc(ctx: rawptr) {
	c := cast(^PageCache)ctx
	_ = c.io.deinit(c.io.data)
	_ = delete(c.pageData)
	_ = delete(c.sets)
	_ = delete(c.path_storage)
	_ = delete(c.base_path)
	_ = delete(c.io_completions)
	free(c)
}

// Inclusive page bounds - empty range returns (0, -1).
cache_page_range :: proc(c: ^PageCache, start, count: i64) -> (min_page, max_page: i64) {
	{
		assert(start >= 0 && count >= 0)
		assert(c.record_size > 0)
	}

	if count == 0 {
		return 0, -1
	}

	{
		assert(count <= max(i64) - start)
		assert(start + count <= max(i64) / c.record_size)
	}

	return (start * c.record_size) / c.page_size, ((start + count) * c.record_size - 1) / c.page_size
}

cache_write :: proc(ctx: rawptr, data: []u8, start: i64, count: i64) {
	c := cast(^PageCache)ctx
	start_page, end_page := cache_page_range(c, start, count)
	cache_acquire_write_pages(c, start_page, end_page)

	write_start := start * c.record_size
	write_end := (start + count) * c.record_size
	for curr_page := start_page; curr_page <= end_page; {
		set := &c.sets[curr_page % i64(len(c.sets))]

		found := false
		waiting := false
		for &p in set.pages {
			if sync.atomic_load_explicit(&p.index, .Acquire) != curr_page {continue}
			found = true
			//TODO: Partial flushes should be using buffers outside page cache
			// Once this is the case, this check and the poll are no longer necessary
			if p.state == .Flushing {
				waiting = true
				break
			}
			{
				assert(p.state == .Clean || p.state == .Dirty)
			}
			page_start := curr_page * c.page_size
			dst_start := max(write_start - page_start, 0)
			dst_end := min(write_end - page_start, c.page_size)
			src_start := page_start + dst_start - write_start
			copy(p.data[dst_start:dst_end], data[src_start:src_start + dst_end - dst_start])
			written_bytes := sync.atomic_add(&p.written_bytes, dst_end - dst_start) + dst_end - dst_start
			{
				assert(written_bytes <= c.page_size)
			}
			break
		}
		{
			assert(found, "pinned page is missing")
		}

		if waiting {
			_, _ = cache_poll(c) // TODO: handle poll errors
			continue
		}
		curr_page += 1
	}


}

//Read a number of contiguous records
cache_read :: proc(ctx: rawptr, data: []u8, start: i64, count: i64) {
	c := cast(^PageCache)ctx
	start_page, end_page := cache_page_range(c, start, count)
	cache_pin_read_pages(c, start_page, end_page)

	read_start := start * c.record_size
	read_end := (start + count) * c.record_size
	for curr_page := start_page; curr_page <= end_page; {
		set := cache_lock_set(c, curr_page % i64(len(c.sets)))

		found := false
		waiting := false
		for &p in set.pages {
			if sync.atomic_load_explicit(&p.index, .Acquire) != curr_page {continue}
			found = true
			{
				assert(sync.atomic_load(&p.ref_count) > 0)
			}
			if p.state == .Read_Pending || p.state == .Loading { 	//Page we need is not yet loaded in
				waiting = true
				break
			}
			{
				assert(p.state == .Clean || p.state == .Dirty || p.state == .Flushing)
			}
			page_start := curr_page * c.page_size
			src_start := max(read_start - page_start, 0)
			src_end := min(read_end - page_start, c.page_size)
			dst_start := page_start + src_start - read_start
			copy(data[dst_start:dst_start + src_end - src_start], p.data[src_start:src_end])
			sync.atomic_sub(&p.ref_count, 1)
			break
		}
		{
			assert(found, "pinned page is missing")
		}
		cache_unlock_set(set)

		if waiting {
			_, _ = cache_poll(c) // TODO: handle poll errors
			continue
		}
		curr_page += 1
	}

}

// Writes through target must have completed before requesting sync.
// TODO: see comments in log for sync
cache_sync :: proc(ctx: rawptr, target: i64) {
	c := cast(^PageCache)ctx
	sync.atomic_store(&c.sync_pending_index, target)
	sync.atomic_store(&c.sync_pending, true)
}

// TODO: implement
cache_drop :: proc(ctx: rawptr, index: i64) {
	c := cast(^PageCache)ctx
	// Need to track/use deleted file index/prefix here
	c.io.unlink(c.io.data, {}, {})
}

//Issue io and handle io completions
cache_poll :: proc(ctx: rawptr) -> (bool, RifleError) {
	c := cast(^PageCache)ctx
	// If another thread in polling, return
	if _, ok := sync.atomic_compare_exchange_strong(&c.polling, 0, 1); ok { 	//TODO: look at memory ordering
		defer (sync.atomic_store(&c.polling, 0))
		for _, set_index in c.sets { 	//TODO: Track pages needing work
			set := cache_lock_set(c, i64(set_index))
			defer cache_unlock_set(set)
			for &p, slot in set.pages {
				i := set_index * SET_ASSOC + slot

				if p.state == .Read_Pending {
					err := c.io.read_at(
						c.io.data,
						{page_index = cast(u32)i, op = .READ, payload = 0},
						p.data,
						cache_file_offset(c, sync.atomic_load_explicit(&p.index, .Acquire)),
						{id = p.file_id, path = p.path},
					)
					if err != nil {
						continue // TODO: handle this properly - likely file isn't open yet
					}
					p.state = .Loading
					continue
				}
				if p.state == .Dirty && sync.atomic_load(&p.written_bytes) == c.page_size {
					err := c.io.write_at(
						c.io.data,
						{page_index = cast(u32)i, op = .WRITE, payload = 0},
						p.data,
						cache_file_offset(c, sync.atomic_load_explicit(&p.index, .Acquire)),
						{id = p.file_id, path = p.path},
					)
					if err != nil {
						continue // TODO: ''
					}
					p.state = .Flushing
					continue
				}
			}
		}

		// Should be last op
		if !c.sync_in_progress {
			if _, pending := sync.atomic_compare_exchange_strong(&c.sync_pending, true, false); pending {
				target := sync.atomic_load(&c.sync_pending_index)
				if err := c.io.sync(c.io.data, {}); err != nil {
					sync.atomic_store(&c.sync_pending, true)
				} else {
					c.sync_index = target
					c.sync_in_progress = true
				}
			}
		}

		// Process IO completions, for each one, update state accordingly
		n, _ := c.io.poll(c.io.data, c.io_completions)

		for ce, _ in c.io_completions[:n] {
			if ce.res < 0 {
				fmt.eprintf("cache %v failed: result %d, page token %d\n", ce.user_data.op, ce.res, ce.user_data.page_index)
			}

			set: ^Set(SET_ASSOC)
			if ce.user_data.op == .READ || ce.user_data.op == .WRITE {
				set = cache_lock_set(c, i64(ce.user_data.page_index) / SET_ASSOC)
			}
			defer {
				if set != nil {cache_unlock_set(set)}
			}

			switch ce.user_data.op {
			case .OPEN: //TODO: Remove
			case .CLOSE: //TODO: Remove

			case .READ:
				p := &c.pages[ce.user_data.page_index]
				if i64(ce.res) != c.page_size {
					if ce.res >= 0 {
						log.debugf("cache read page %d: expected %d bytes, got %d", sync.atomic_load_explicit(&p.index, .Acquire), c.page_size, ce.res)
					}
					p.state = .Read_Pending
					continue
				}
				p.state = .Clean
				p.written_bytes = i64(ce.res)

			case .WRITE:
				p := &c.pages[ce.user_data.page_index]
				if i64(ce.res) != c.page_size {
					if ce.res >= 0 {
						log.debugf("cache write page %d: expected %d bytes, got %d", sync.atomic_load_explicit(&p.index, .Acquire), c.page_size, ce.res)
					}
					p.state = .Dirty
					continue
				}
				p.state = .Clean
				set.lru = lru_update(set.lru, u8(ce.user_data.page_index % SET_ASSOC))

			case .SYNC:
				c.sync_in_progress = false
				if ce.res == 0 {
					sync.atomic_store(c.durable_index, c.sync_index)
				}
			case .DELETE:
			}
		}
		return true, nil
	}
	return false, nil
}

@(private)
cache_file_offset :: proc(c: ^PageCache, page_index: i64) -> u64 {
	return u64((page_index % c.pages_per_file) * c.page_size)
}

@(private)
cache_lock_set :: proc(c: ^PageCache, set_index: i64) -> ^Set(SET_ASSOC) {
	set := &c.sets[set_index]
	for ok := false; !ok; {
		_, ok = sync.atomic_compare_exchange_strong(&set.lock, 0, 1)
	}
	return set
}

@(private)
cache_unlock_set :: proc(set: ^Set(SET_ASSOC)) {
	sync.atomic_store(&set.lock, 0)
}

@(private)
cache_find_page :: proc(set: ^Set(SET_ASSOC), page_index: i64) -> (page: ^Page, slot: u8) {
	for &p, i in set.pages {
		if sync.atomic_load_explicit(&p.index, .Acquire) == page_index {
			return &p, u8(i)
		}
	}
	return nil, 0
}

// Caller must hold the set lock
@(private)
cache_find_or_allocate_page :: proc(c: ^PageCache, set: ^Set(SET_ASSOC), page_index: i64, initial_state: PageState) -> (page: ^Page, slot: u8) {
	if p, i := cache_find_page(set, page_index); p != nil {
		return p, i
	}

	for i in lru_get_order(set.lru) {
		p := &set.pages[i]
		if (p.state == .Empty || (p.state == .Clean && p.written_bytes == c.page_size)) && sync.atomic_load(&p.ref_count) == 0 {
			sync.atomic_store_explicit(&p.index, -1, .Release)
			file_id := page_index / c.pages_per_file
			path := fmt.bprintf(p.path_buffer[:len(p.path_buffer) - 1], "%s/%s%d%s", c.base_path, DATA_PREFIX, file_id, FILE_EXTENSION)
			p.path_buffer[len(path)] = 0
			p.file_id = file_id
			p.path = cstring(raw_data(p.path_buffer))
			p.written_bytes = 0
			p.ref_count = 0
			p.state = initial_state
			sync.atomic_store_explicit(&p.index, page_index, .Release)
			return p, i
		}
	}
	return nil, 0
}

@(private)
cache_pin_read_pages :: proc(c: ^PageCache, start_page, end_page: i64) {
	// TODO: acquire pages in chunks
	for curr_page := start_page; curr_page <= end_page; {
		set := cache_lock_set(c, curr_page % i64(len(c.sets)))
		p, slot := cache_find_or_allocate_page(c, set, curr_page, .Read_Pending)
		if p != nil {
			sync.atomic_add(&p.ref_count, 1)
			set.lru = lru_update(set.lru, slot)
		}
		cache_unlock_set(set)

		if p == nil {
			_, _ = cache_poll(c) // TODO: handle poll errors
			continue
		}
		curr_page += 1
	}
}

@(private)
cache_acquire_write_pages :: proc(c: ^PageCache, start_page, end_page: i64) {
	// TODO: acquire pages in chunks
	for curr_page := start_page; curr_page <= end_page; {
		set_index := curr_page % i64(len(c.sets))
		set := &c.sets[set_index]
		p, _ := cache_find_page(set, curr_page)
		if p == nil {
			set = cache_lock_set(c, set_index)
			p, _ = cache_find_or_allocate_page(c, set, curr_page, .Dirty)
			cache_unlock_set(set)
		}

		if p == nil {
			_, _ = cache_poll(c) // TODO: handle poll errors
			continue
		}
		curr_page += 1
	}
}
