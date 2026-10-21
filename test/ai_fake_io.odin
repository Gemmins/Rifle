package test

import rifle "rifle:rifle"


Fake_IO :: struct {
	requests:     [dynamic]Fake_IO_Request,
	completions:  [dynamic]rifle.IOCompletion,
	cache_buffer: []u8,
	capacity:     int,
	next_error:   rifle.RifleError,
	poll_error:   rifle.RifleError,
}

Fake_IO_Request :: struct {
	user_data: rifle.IOUserData,
	file:      rifle.RifleFile,
	buffer:    []u8,
	offset:    u64,
}

Fake_IO_Interface :: rifle.IO_Impl(Fake_IO, fake_io_init, fake_io_deinit, fake_io_open, fake_io_close, fake_io_read, fake_io_write, fake_io_sync, fake_io_delete, fake_io_poll)
Fake_PageCache :: rifle.PageCache_Impl(Fake_IO_Interface)

fake_io :: proc(f: ^Fake_IO) -> ^Fake_IO {
	return f
}

fake_io_init :: proc(ctx: rawptr, buffer: []u8) -> rifle.RifleError {
	f := cast(^Fake_IO)ctx
	f.cache_buffer = buffer
	return nil
}

fake_io_deinit :: proc(ctx: rawptr) -> rifle.RifleError {
	f := cast(^Fake_IO)ctx
	delete(f.requests)
	delete(f.completions)
	f^ = {}
	return nil
}

fake_io_queue :: proc(
	f: ^Fake_IO,
	op: rifle.IOOperation,
	data: rifle.IOUserData,
	file: rifle.RifleFile = {},
	buffer: []u8 = nil,
	offset: u64 = 0,
) -> rifle.RifleError {
	if f.next_error != nil {
		err := f.next_error
		f.next_error = nil
		return err
	}
	if f.capacity > 0 && len(f.requests) >= f.capacity {return .GenericError}
	data := data
	data.op = op
	append(&f.requests, Fake_IO_Request{data, file, buffer, offset})
	return nil
}

fake_io_open :: proc(ctx: rawptr, data: rifle.IOUserData, file: rifle.RifleFile) -> rifle.RifleError {
	return fake_io_queue(cast(^Fake_IO)ctx, .OPEN, data, file)
}
fake_io_close :: proc(ctx: rawptr, data: rifle.IOUserData, file: rifle.RifleFile) -> rifle.RifleError {
	return fake_io_queue(cast(^Fake_IO)ctx, .CLOSE, data, file)
}
fake_io_read :: proc(ctx: rawptr, data: rifle.IOUserData, buffer: []u8, offset: u64, file: rifle.RifleFile) -> rifle.RifleError {
	return fake_io_queue(cast(^Fake_IO)ctx, .READ, data, file, buffer, offset)
}
fake_io_write :: proc(ctx: rawptr, data: rifle.IOUserData, buffer: []u8, offset: u64, file: rifle.RifleFile) -> rifle.RifleError {
	return fake_io_queue(cast(^Fake_IO)ctx, .WRITE, data, file, buffer, offset)
}
fake_io_sync :: proc(ctx: rawptr, data: rifle.IOUserData) -> rifle.RifleError {
	return fake_io_queue(cast(^Fake_IO)ctx, .SYNC, data)
}
fake_io_delete :: proc(ctx: rawptr, data: rifle.IOUserData, file: rifle.RifleFile) -> rifle.RifleError {
	return fake_io_queue(cast(^Fake_IO)ctx, .DELETE, data, file)
}

// Complete any queued request. Supply events for implicit opens or sync batches.
// Otherwise emit one completion with the request's token and the supplied result.
fake_io_complete :: proc(f: ^Fake_IO, index: int, res: i32, read_data: []u8 = nil, events: []rifle.IOCompletion = nil) {
	assert(index >= 0 && index < len(f.requests))
	r := f.requests[index]
	if r.user_data.op == .READ && res > 0 {
		assert(int(res) <= len(r.buffer) && int(res) <= len(read_data))
		copy(r.buffer[:res], read_data[:res])
	}
	if r.user_data.op == .WRITE && res > 0 {assert(int(res) <= len(r.buffer))}
	if events != nil {
		append(&f.completions, ..events)
	} else {
		append(&f.completions, rifle.IOCompletion{user_data = r.user_data, res = res})
	}
	ordered_remove(&f.requests, index)
}

fake_io_poll :: proc(ctx: rawptr, output: []rifle.IOCompletion) -> (u32, rifle.RifleError) {
	f := cast(^Fake_IO)ctx
	if f.poll_error != nil {
		err := f.poll_error
		f.poll_error = nil
		return 0, err
	}
	n := min(len(output), len(f.completions))
	copy(output[:n], f.completions[:n])
	for _ in 0 ..< n {ordered_remove(&f.completions, 0)}
	return u32(n), nil
}
