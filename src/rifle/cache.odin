package rifle

import "base:runtime"

Cache :: struct {
	data:   rawptr,
	init:   proc(
		ctx: rawptr,
		capacity_in_bytes: i64,
		page_size: i64,
		io: IO,
		base_path: string,
		file_size: i64,
		durable_index: ^i64,
	) -> runtime.Allocator_Error,
	deinit: proc(ctx: rawptr),
	read:   proc(ctx: rawptr, data: []u8, start: i64, count: i64),
	write:  proc(ctx: rawptr, data: []u8, start: i64, count: i64),
	poll:   proc(ctx: rawptr) -> (bool, RifleError),
	sync:   proc(ctx: rawptr, target: i64),
}
