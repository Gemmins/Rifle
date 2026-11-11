package rifle

Cache :: struct {
	data:   rawptr,
	init:   proc(
		ctx: rawptr,
		capacity_in_bytes: i64,
		page_size: i64,
		io: IO,
		base_path: string,
		file_size: i64,
		record_size: i64,
		durable_index: ^i64,
	) -> RifleError,
	deinit: proc(ctx: rawptr) -> RifleError,
	read:   proc(ctx: rawptr, data: []u8, start: i64, count: i64) -> RifleError,
	write:  proc(ctx: rawptr, data: []u8, start: i64, count: i64) -> RifleError,
	poll:   proc(ctx: rawptr) -> (bool, RifleError),
	sync:   proc(ctx: rawptr, target: i64),
	drop:   proc(ctx: rawptr, index: i64),
}
