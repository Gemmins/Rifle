package rifle

import "base:runtime"
import "core:fmt"
import "core:mem"

SET_ASSOC :: 4

PageCache :: struct {
	pages:    []Page,
	pageData: []u8,
	sets:     []Set(SET_ASSOC),
}

Page :: struct {
	data:         []u8,
	index:        i64,
	record_count: i64,
	ref_count:    i64,
	state:        PageState,
}

PageState :: enum u32 {
	Empty,
	Waiting_For_File_Read,
	Loading,
	Clean,
	Dirty,
	Waiting_For_File_Write,
	Flushing,
}

Set :: struct($Assoc: i64) {
	pages: [Assoc]Page,
	lock:  u32,
}

RifleFile :: struct {
	id:   i64,
	path: cstring,
}

page_cache_init :: proc(c: ^PageCache, capacity_in_bytes: i64, page_size: i64 = 1 << 12) -> runtime.Allocator_Error {
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

	return nil
}

cache_write :: proc(c: ^PageCache, data: []u8, start: i64, count: i64) {
	// Look for page
	// If in cache - write
	// Else - get_for_write - write
}

cache_read :: proc(c: ^PageCache, data: []u8, start: i64, count: i64) {
	// Look for page
	// If in cache - read
	// Else - get_for_read - read
}

@(private)
get_for_read :: proc(page_index: i64) {

}

@(private)
get_for_write :: proc(page_index: i64) {

}

main :: proc() {
	c := PageCache{}
	page_cache_init(&c, 4096 * 256)
	fmt.println(c.pages[0])
}
