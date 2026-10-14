package rifle

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:sync"

SET_ASSOC :: 4 // LRU impl requires 4

PageCache :: struct {
	pages:          []Page,
	pageData:       []u8,
	sets:           []Set(SET_ASSOC),
	files:          []RifleFile,
	io:             IO,
	io_completions: []IOCompletion,
	polling:        i64,
	sync_pending:   bool,
	record_size:    i64,
}

Page :: struct {
	data:         []u8,
	index:        i64,
	record_count: i64,
	ref_count:    i64,
	state:        PageState,
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
	lock:  u32,
	lru:   lru,
}

RifleFile :: struct {
	id:   i64,
	path: cstring,
}

page_cache_init :: proc(c: ^PageCache, capacity_in_bytes: i64, page_size: i64 = 1 << 13) -> runtime.Allocator_Error {
	num_pages := capacity_in_bytes / page_size
	backing := make([]u8, num_pages * (page_size + size_of(Page)), context.allocator)
	split_point := num_pages * size_of(Page)
	c.pages = mem.slice_data_cast([]Page, backing[:split_point])
	c.pageData = backing[split_point:]
	for &v, i in c.pages {
		v.data = c.pageData[cast(i64)i * page_size:(cast(i64)i + 1) * page_size]
		v.index = -1
	}

	c.sets = make([]Set(SET_ASSOC), num_pages / SET_ASSOC)
	for &s, i in c.sets {
		s.pages = c.pages[i:i + SET_ASSOC]
		s.lru = lru_new()
	}

	c.files = make([]RifleFile, 128, context.allocator) //TODO: count

	c.io_completions = make([]IOCompletion, 128, context.allocator) //TODO: count

	return nil
}

cache_write :: proc(c: ^PageCache, data: []u8, start: i64, count: i64) {
	// Look for page(s) - in loop
	// If in cache - write
	// Else - get_for_write - write
}

cache_read :: proc(c: ^PageCache, data: []u8, start: i64, count: i64) {
	// Look for page(s) - in loop
	// If in cache - read
	// Else - get_for_read - read
}

cache_poll :: proc(c: ^PageCache) -> (bool, RifleError) {
	// If another thread in polling, return
	if _, ok := sync.atomic_compare_exchange_strong(&c.polling, 0, 1); ok { 	//TODO: memory ordering
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
		return true, nil
	}
	return false, nil
}

cache_sync :: proc(c: ^PageCache) {
	sync.atomic_store(&c.sync_pending, true)
}

@(private)
get_for_read :: proc(page_index: i64) {

}

@(private)
get_for_write :: proc(page_index: i64) {

}
