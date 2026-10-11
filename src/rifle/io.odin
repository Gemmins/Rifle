package rifle

IO :: struct {
	data:     rawptr,
	init:     proc(ctx: rawptr, cache_buffer: []u8) -> RifleError,
	deinit:   proc(ctx: rawptr) -> RifleError,
	open:     proc(ctx: rawptr, user_data: IOUserData, file: RifleFile) -> RifleError,
	close:    proc(ctx: rawptr, user_data: IOUserData, file: RifleFile) -> RifleError,
	read_at:  proc(ctx: rawptr, user_data: IOUserData, buffer: []u8, offset: u64, file: RifleFile) -> RifleError,
	write_at: proc(ctx: rawptr, user_data: IOUserData, buffer: []u8, offset: u64, file: RifleFile) -> RifleError,
	sync:     proc(ctx: rawptr, user_data: IOUserData) -> RifleError,
	delete:   proc(ctx: rawptr, user_data: IOUserData, file: RifleFile) -> RifleError,
	poll:     proc(ctx: rawptr, completions: []IOCompletion) -> (u32, RifleError),
}

IOCompletion :: struct {
	user_data: IOUserData,
	res:       i32,
}

IOUserData :: bit_field u64 {
	page_index: u32         | 24,
	file_index: u16         | 12,
	op:         IOOperation | 4,
	payload:    u32         | 24,
}

//!NO LARGER THAN 4 BITS!
IOOperation :: enum u8 {
	OPEN,
	CLOSE,
	READ,
	WRITE,
	SYNC,
	DELETE,
}
