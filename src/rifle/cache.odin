package rifle

import "base:runtime"


Cache_Impl :: struct(
	$State: typeid,
	$init: proc(
		ctx: rawptr,
		capacity_in_bytes: i64,
		page_size: i64,
		io_state: ^IO.State,
		base_path: string,
		file_size: i64,
		durable_index: ^i64,
	) -> runtime.Allocator_Error,
	$deinit: proc(ctx: rawptr),
	$read: proc(ctx: rawptr, data: []u8, start: i64, count: i64),
	$write: proc(ctx: rawptr, data: []u8, start: i64, count: i64),
	$poll: proc(ctx: rawptr) -> (bool, RifleError),
	$sync: proc(ctx: rawptr, target: i64),
) {
	data: ^State,
}

Cache :: Cache_Impl(PageCache, page_cache_init, page_cache_deinit, page_cache_read, page_cache_write, page_cache_poll, page_cache_sync)

new_page_cache :: proc() -> Cache {
	return {data = new(PageCache, context.allocator)}
}

@(private)
page_cache_init :: proc(
	ctx: rawptr,
	capacity_in_bytes: i64,
	page_size: i64,
	io_state: ^IO.State,
	base_path: string,
	file_size: i64,
	durable_index: ^i64,
) -> runtime.Allocator_Error {
	return cache_init(cast(^PageCache)ctx, capacity_in_bytes, page_size, io_state, base_path, file_size, durable_index)
}

@(private)
page_cache_deinit :: proc(ctx: rawptr) {
	c := cast(^PageCache)ctx
	cache_delete(c)
	free(c)
}

@(private)
page_cache_read :: proc(ctx: rawptr, data: []u8, start: i64, count: i64) {
	cache_read(cast(^PageCache)ctx, data, start, count)
}

@(private)
page_cache_write :: proc(ctx: rawptr, data: []u8, start: i64, count: i64) {
	cache_write(cast(^PageCache)ctx, data, start, count)
}

@(private)
page_cache_poll :: proc(ctx: rawptr) -> (bool, RifleError) {
	return cache_poll(cast(^PageCache)ctx)
}

@(private)
page_cache_sync :: proc(ctx: rawptr, target: i64) {
	cache_sync(cast(^PageCache)ctx, target)
}
