package rifle

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:sync"

SET_ASSOC :: 4 // LRU impl requires 4

PageCache :: struct {
	page_size:      i64,
	num_pages:      i64,
	pages:          []Page,
	pageData:       []u8,
	sets:           []Set(SET_ASSOC),
	files:          []RifleFile,
	io:             IO,
	io_completions: []IOCompletion,
	record_size:    i64,
	polling:        u32,
	sync_pending:   bool,
}

Page :: struct {
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

RifleFile :: struct {
	id:    i64,
	path:  cstring,
	state: RifleFileState,
}

RifleFileState :: enum u32 {
	Closed, // File has been closed - can be evicted
	Opening, // File is in the process of being opened
	Open, // File is open
	ToClose, // File is marked for closure
	Closing, // File is in the process of being closed
}

cache_init :: proc(c: ^PageCache, capacity_in_bytes: i64, page_size: i64 = 1 << 13, io: IO) -> runtime.Allocator_Error {
	c.page_size = page_size
	num_pages := capacity_in_bytes / page_size
	c.num_pages = num_pages // Probs require some enforcement around this and assoc to ensure divisble

	backing := make_aligned([]u8, num_pages * (page_size + size_of(Page)), 1 << 12, context.allocator) // Alignment here will at some point be driven by system settings
	split_point := num_pages * page_size
	c.pages = mem.slice_data_cast([]Page, backing[split_point:])
	c.pageData = backing[:split_point]
	for &v, i in c.pages {
		v.data = c.pageData[cast(i64)i * page_size:(cast(i64)i + 1) * page_size]
		v.index = -1
	}

	c.sets = make([]Set(SET_ASSOC), num_pages / SET_ASSOC)
	for &s, i in c.sets {
		s.pages = c.pages[(i * SET_ASSOC):(i * SET_ASSOC) + SET_ASSOC]
		s.lru = lru_new()
	}

	c.files = make([]RifleFile, 128, context.allocator) //TODO: actual count

	c.io_completions = make([]IOCompletion, 128, context.allocator) //TODO: actual count
	c.io = io
	c.io.init(c.io.data, c.pageData)

	return nil
}

cache_delete :: proc(c: ^PageCache) {
	_ = delete(c.pageData)
	_ = delete(c.sets)
	_ = delete(c.files)
	_ = delete(c.io_completions)
	_ = c.io.deinit(c.io.data)
}

// Inclusive page bounds - empty range returns (0, -1).
cache_page_range :: proc(c: ^PageCache, start, count: i64) -> (min_page, max_page: i64) {
	{
		assert(start >= 0 && count >= 0)
		assert(c.record_size > 0 && c.page_size > 0)
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

//Write a number of contiguous records
cache_write :: proc(c: ^PageCache, data: []u8, start: i64, count: i64) {
	// Look for page(s) - in loop
	// This loop should just get every page locked in the cache - then a second loop to copy from the users buffer.
	// This will eventually be done in chunks of pages to avoid locking large amounts of pages in the cache.
	start_page, end_page := cache_page_range(c, start, count)
	{
		assert(i64(len(data)) >= count * c.record_size)
	}
	for curr_page := start_page; curr_page <= end_page; {
		set_idx := curr_page % i64(len(c.sets))
		set := &c.sets[set_idx]

		for ok := false; !ok; { 	//TODO: revisit what this lock is around
			_, ok = sync.atomic_compare_exchange_strong(&set.lock, 0, 1)
		}

		found := false
		for &p, i in set.pages {
			if p.index == curr_page {
				sync.atomic_add(&p.ref_count, 1) // Lock page
				set.lru = lru_update(set.lru, cast(u8)i)
				found = true
				break
			}
		}

		if !found {
			lru_order := lru_get_order(set.lru)
			for i, _ in lru_order {
				p := &set.pages[i]
				if (p.state == .Empty || (p.state == .Clean && p.written_bytes == c.page_size)) && sync.atomic_load(&p.ref_count) == 0 {
					set.pages[i] = {
						data      = set.pages[i].data,
						index     = curr_page,
						state     = .Clean,
						ref_count = 1,
					}
					set.lru = lru_update(set.lru, i)
					found = true
					break
				}
			}
		}

		sync.atomic_store(&set.lock, 0)
		if !found { 	// In the case of a failed eviction we advance the cache and try again wholly
			_, _ = cache_poll(c) // TODO: handle poll results
			continue
		}
		curr_page += 1
	}

	// All pages now locked in the cache
	// - Iterate over each one
	// - Copy appropriate record range
	// - Make page dirty
	// - Decrement ref_count
	// - We could _maybe_ do some log accounting here to update visible index but may be simplest to avoid
	write_start := start * c.record_size
	write_end := (start + count) * c.record_size
	for curr_page := start_page; curr_page <= end_page; {
		set := &c.sets[curr_page % i64(len(c.sets))]
		for ok := false; !ok; {
			_, ok = sync.atomic_compare_exchange_strong(&set.lock, 0, 1)
		}

		found := false
		waiting := false
		for &p in set.pages {
			if p.index != curr_page {continue}
			found = true
			{
				assert(sync.atomic_load(&p.ref_count) > 0)
			}
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
			p.written_bytes += dst_end - dst_start
			{
				assert(p.written_bytes <= c.page_size)
			}
			p.state = .Dirty
			sync.atomic_sub(&p.ref_count, 1)
			break
		}
		{
			assert(found, "pinned page is missing")
		}
		sync.atomic_store(&set.lock, 0)
		if waiting {
			_, _ = cache_poll(c) // TODO: handle poll results
			continue
		}
		curr_page += 1
	}


}

//Read a number of contiguous records
cache_read :: proc(c: ^PageCache, data: []u8, start: i64, count: i64) {
	// Look for page(s) - in loop
	// If in cache - read
	// Else - get_for_read - poll until ready or wait on poll - read
	//
}

//Issue io and handle io completions
cache_poll :: proc(c: ^PageCache) -> (bool, RifleError) {
	// If another thread in polling, return
	if _, ok := sync.atomic_compare_exchange_strong(&c.polling, 0, 1); ok { 	//TODO: look at memory ordering
		// Iterate over files, pages
		// At each one, depending on state, issue io, change state
		for f, _ in c.files {
			fmt.println(f)
		}

		for p, _ in c.pages {
			fmt.println(p)
		}

		// Should be last op
		if _, sync_pending := sync.atomic_compare_exchange_strong(&c.sync_pending, true, false); sync_pending {
			_ = c.io.sync(c.io.data, {}) // TODO: pass something useful here
		}

		// Process IO completions, for each one, update state accordingly
		c.io.poll(c.io.data, c.io_completions)
		for c, _ in c.io_completions {
			fmt.println(c)
		}

		sync.atomic_store(&c.polling, 0)
		return true, nil
	}
	return false, nil
}

//Force some data to become durable (who knows how much? :)
cache_sync :: proc(c: ^PageCache) {
	sync.atomic_store(&c.sync_pending, true)
}

@(private)
get_for_read :: proc(page_index: i64) {

}

@(private)
get_for_write :: proc(page_index: i64) {

}
