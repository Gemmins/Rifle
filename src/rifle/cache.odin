package rifle

Cache :: struct {
	data:   rawptr,
	init:   proc(
		ctx: rawptr,
		ring_capacity: i64,
		page_capacity: i64,
		page_size: i64,
		commit_ring_size: i64,
		io: IO,
		file_size: i64,
		record_size: i64,
		visible_index: ^i64,
		persisted_index: ^i64,
		durable_index: ^i64,
		dropped_index: ^i64,
		read_chunk_size: i64 = 0,
	) -> RifleError,
	deinit: proc(ctx: rawptr) -> RifleError,
	read:   proc(ctx: rawptr, data: []u8, start: i64, count: i64) -> RifleError,
	write:  proc(ctx: rawptr, data: []u8, start: i64, count: i64) -> RifleError,
	poll:   proc(ctx: rawptr) -> (bool, RifleError),
	sync:   proc(ctx: rawptr),
}
