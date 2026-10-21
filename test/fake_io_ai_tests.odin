package test

import "core:testing"
import rifle "rifle:rifle"

@(test)
fake_io_delayed_transfers :: proc(t: ^testing.T) {
	f: Fake_IO
	io := fake_io(&f)
	defer Fake_IO_Interface.deinit(io)
	buffer := [8]u8{1, 2, 3, 4, 9, 9, 9, 9}
	testing.expect(t, Fake_IO_Interface.init(io, buffer[:]) == nil)
	file := rifle.RifleFile{id = 42}
	write := rifle.IOUserData{op = .WRITE, page_index = u32(7), payload = 1}
	read := rifle.IOUserData{op = .READ, page_index = u32(7), payload = 2}
	testing.expect(t, Fake_IO_Interface.write_at(io, write, buffer[:4], 16, file) == nil)
	testing.expect(t, Fake_IO_Interface.read_at(io, read, buffer[4:], 32, file) == nil)
	testing.expect(t, len(f.requests) == 2 && f.requests[0].offset == 16 && f.requests[1].file.id == 42)
	testing.expect(t, f.requests[0].buffer[0] == 1)
	out: [1]rifle.IOCompletion
	n, err := Fake_IO_Interface.poll(io, out[:])
	testing.expect(t, n == 0 && err == nil && buffer[4] == 9)
	// Read completes first, and only fills the returned byte count.
	fake_io_complete(&f, 1, 2, buffer[:2])
	fake_io_complete(&f, 0, 4)
	n, err = Fake_IO_Interface.poll(io, out[:0])
	testing.expect(t, n == 0 && len(f.completions) == 2)
	n, err = Fake_IO_Interface.poll(io, out[:])
	testing.expect(t, n == 1 && err == nil && out[0].user_data == read && out[0].res == 2)
	testing.expect(t, buffer[4] == 1 && buffer[5] == 2 && buffer[6] == 9)
	n, err = Fake_IO_Interface.poll(io, out[:])
	testing.expect(t, n == 1 && out[0].user_data == write && out[0].res == 4)
	testing.expect(t, len(f.requests) == 0 && len(f.completions) == 0)
}

@(test)
fake_io_errors_and_batches :: proc(t: ^testing.T) {
	f := Fake_IO{capacity = 1, next_error = .FileOperationError}
	io := fake_io(&f)
	defer Fake_IO_Interface.deinit(io)
	testing.expect(t, Fake_IO_Interface.open(io, {}, {id = 1}) == .FileOperationError)
	testing.expect(t, len(f.requests) == 0)
	testing.expect(t, Fake_IO_Interface.open(io, {}, {id = 1}) == nil)
	testing.expect(t, Fake_IO_Interface.close(io, {}, {id = 1}) == .GenericError)
	fake_io_complete(&f, 0, -5)
	f.poll_error = .GenericError
	out: [4]rifle.IOCompletion
	n, err := Fake_IO_Interface.poll(io, out[:])
	testing.expect(t, n == 0 && err == .GenericError && len(f.completions) == 1)
	n, err = Fake_IO_Interface.poll(io, out[:])
	testing.expect(t, n == 1 && err == nil && out[0].res == -5)
	testing.expect(t, Fake_IO_Interface.sync(io, {payload = 9}) == nil)
	events := [2]rifle.IOCompletion{
		{user_data = {op = .SYNC, page_index = u32(1), payload = 9}},
		{user_data = {op = .SYNC, page_index = u32(2), payload = 9}},
	}
	fake_io_complete(&f, 0, 0, events = events[:])
	n, err = Fake_IO_Interface.poll(io, out[:])
	testing.expect(t, n == 2 && out[0] == events[0] && out[1] == events[1])
	testing.expect(t, Fake_IO_Interface.close(io, {}, {id = 1}) == nil)
	fake_io_complete(&f, 0, 0)
	testing.expect(t, Fake_IO_Interface.delete(io, {}, {id = 1}) == nil)
	fake_io_complete(&f, 0, 0)
	n, err = Fake_IO_Interface.poll(io, out[:])
	testing.expect(t, n == 2 && out[0].user_data.op == .CLOSE && out[1].user_data.op == .DELETE)
}
