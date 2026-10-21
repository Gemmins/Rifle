package test

import "core:testing"
import "rifle:rifle"

@(test)
cache_page_range :: proc(t: ^testing.T) {
	pc := rifle.PageCache {
		page_size   = 16,
		record_size = 4,
		num_pages   = 4,
	}
	path_storage: [512]u8
	ai_cache_paths(&pc, path_storage[:])
	cases := [?]struct {
		start, count, first, last: i64,
	}{{0, 0, 0, -1}, {2, 1, 0, 0}, {0, 4, 0, 0}, {4, 4, 1, 1}, {3, 2, 0, 1}, {3, 10, 0, 3}, {20, 8, 5, 6}}
	for tc in cases {
		first, last := rifle.cache_page_range(&pc, tc.start, tc.count)
		testing.expect_value(t, first, tc.first)
		testing.expect_value(t, last, tc.last)
	}
	pc.record_size = 6
	first, last := rifle.cache_page_range(&pc, 2, 1)
	testing.expect(t, first == 0 && last == 1)
	pc.record_size = 40
	first, last = rifle.cache_page_range(&pc, 0, 1)
	testing.expect(t, first == 0 && last == 2)
}

@(test)
cache_write_copies_page_ranges :: proc(t: ^testing.T) {
	cases := [?]struct {
		record_size, start, count: i64,
	}{{4, 1, 1}, {4, 3, 10}, {6, 3, 7}, {40, 0, 2}, {4, 0, 0}}
	for tc in cases {
		backing: [128]u8
		for &b in backing {b = 0xee}
		pages: [8]rifle.Page
		sets: [2]rifle.Set(rifle.SET_ASSOC)
		for &s, i in sets {
			s.pages = pages[i * 4:(i + 1) * 4]
			s.lru = rifle.lru_new()
			for &p, j in s.pages {
				index := i + j * 2
				p = {
					data  = backing[index * 16:(index + 1) * 16],
					index = i64(index),
					state = .Clean,
				}
			}
		}
		pc := rifle.PageCache {
			page_size   = 16,
			num_pages   = 8,
			record_size = tc.record_size,
			pages       = pages[:],
			sets        = sets[:],
		}
		path_storage: [512]u8
		ai_cache_paths(&pc, path_storage[:])
		source: [128]u8
		for &b, i in source {b = u8(i)}
		n := tc.count * tc.record_size
		rifle.cache_write(&pc, source[:n], tc.start, tc.count)
		begin := tc.start * tc.record_size
		for b, i in backing {
			expected := u8(0xee)
			if i64(i) >= begin && i64(i) < begin + n {expected = source[i64(i) - begin]}
			testing.expect_value(t, b, expected)
		}
		for p in pages {
			touched := n > 0 && p.index * 16 < begin + n && (p.index + 1) * 16 > begin
			testing.expect(t, p.state == (touched ? .Dirty : .Clean))
			testing.expect_value(t, p.ref_count, i64(0))
		}
		for s in sets {testing.expect_value(t, s.lock, u32(0))}
	}
}

@(test)
cache_write_keeps_partial_pages :: proc(t: ^testing.T) {
	empty_values := [2]bool{false, true}
	for use_empty in empty_values {
		backing: [64]u8
		pages: [4]rifle.Page
		for &p, i in pages {
			p = {
				data          = backing[i * 16:(i + 1) * 16],
				index         = i64(i),
				state         = .Clean,
				written_bytes = 16,
			}
		}
		pages[0].written_bytes = 4 // Partial, even though clean.
		pages[1].ref_count = 1 // Full but pinned.
		pages[2].state = .Dirty // Full but not flushed.
		if use_empty {
			pages[3].state = .Empty
			pages[3].index = -1
			pages[3].written_bytes = 0
		}
		sets := [1]rifle.Set(rifle.SET_ASSOC){{pages = pages[:], lru = rifle.lru_new()}}
		pc := rifle.PageCache {
			page_size   = 16,
			num_pages   = 4,
			record_size = 4,
			sets        = sets[:],
		}
		path_storage: [512]u8
		ai_cache_paths(&pc, path_storage[:])
		data: [16]u8
		rifle.cache_write(&pc, data[:4], 16, 1)
		testing.expect(t, pages[0].index == 0 && pages[0].written_bytes == 4)
		testing.expect(t, pages[1].index == 1 && pages[1].ref_count == 1)
		testing.expect(t, pages[2].index == 2 && pages[2].state == .Dirty)
		testing.expect(t, pages[3].index == 4 && pages[3].written_bytes == 4)
		rifle.cache_write(&pc, data[:12], 17, 3)
		testing.expect(t, pages[3].written_bytes == 16 && pages[3].ref_count == 0)
	}
}

@(test)
cache_write_waits_for_flush :: proc(t: ^testing.T) {
	backing: [16]u8
	pages := [4]rifle.Page{{data = backing[:], index = 0, state = .Flushing, written_bytes = 4}, {index = -1}, {index = -1}, {index = -1}}
	sets := [1]rifle.Set(rifle.SET_ASSOC){{pages = pages[:], lru = rifle.lru_new()}}
	pc := AI_Flush_Wait_Cache {
		page_size   = 16,
		num_pages   = 4,
		record_size = 4,
		sets        = sets[:],
	}
	path_storage: [512]u8
	ai_cache_paths(&pc, path_storage[:])
	state := AI_Flush_Wait_State {
		t     = t,
		sets = pc.sets,
	}
	pc.io_state = &state
	data := [4]u8{1, 2, 3, 4}
	rifle.cache_write(&pc, data[:], 1, 1)
	testing.expect_value(t, state.calls, 2)
	testing.expect(t, pages[0].state == .Dirty && pages[0].written_bytes == 8)
	testing.expect_value(t, pages[0].ref_count, i64(0))
	for b, i in data {testing.expect_value(t, backing[4 + i], b)}
}

@(test)
cache_read_copies_page_ranges :: proc(t: ^testing.T) {
	cases := [?]struct {record_size, start, count: i64}{
		{4, 1, 1}, {4, 3, 10}, {6, 3, 7}, {40, 0, 2}, {4, 0, 0},
	}
	states := [3]rifle.PageState{.Clean, .Dirty, .Flushing}
	for tc in cases {
		backing: [128]u8
		for &b, i in backing {b = u8(i)}
		pages: [8]rifle.Page
		sets: [2]rifle.Set(rifle.SET_ASSOC)
		for &s, i in sets {
			s.pages = pages[i * 4:(i + 1) * 4]
			s.lru = rifle.lru_new()
			for &p, j in s.pages {
				index := i + j * 2
				p = {data = backing[index * 16:(index + 1) * 16], index = i64(index),
				     state = states[index % 3], written_bytes = 16, ref_count = 1}
			}
		}
		pc := rifle.PageCache{page_size = 16, num_pages = 8, record_size = tc.record_size, sets = sets[:]}
		path_storage: [512]u8
		ai_cache_paths(&pc, path_storage[:])
		output: [128]u8
		for &b in output {b = 0xee}
		rifle.cache_read(&pc, output[:], tc.start, tc.count)
		for b, i in output {
			expected := i64(i) < tc.count * tc.record_size ? u8(tc.start * tc.record_size + i64(i)) : u8(0xee)
			testing.expect_value(t, b, expected)
		}
		for p in pages {
			testing.expect_value(t, p.state, states[p.index % 3])
			testing.expect_value(t, p.written_bytes, i64(16))
			testing.expect_value(t, p.ref_count, i64(1))
		}
		for b, i in backing {testing.expect_value(t, b, u8(i))}
		for s in sets {testing.expect_value(t, s.lock, u32(0))}
	}
}

@(test)
cache_read_waits_for_loading :: proc(t: ^testing.T) {
	backing: [64]u8
	pages: [4]rifle.Page
	for &p, i in pages {p = {data = backing[i * 16:(i + 1) * 16], index = -1}}
	sets := [1]rifle.Set(rifle.SET_ASSOC){{pages = pages[:], lru = rifle.lru_new()}}
	pc := AI_Read_Wait_Cache{page_size = 16, num_pages = 4, record_size = 4, sets = sets[:]}
	path_storage: [512]u8
	ai_cache_paths(&pc, path_storage[:])
	output := [4]u8{0xee, 0xee, 0xee, 0xee}
	state := AI_Read_Wait_State{t = t, sets = pc.sets, output = output[:]}
	pc.io_state = &state
	rifle.cache_read(&pc, output[:], 1, 1)
	testing.expect_value(t, state.calls, 2)
	for b, i in output {testing.expect_value(t, b, u8(i + 4))}
	for p in pages {
		testing.expect_value(t, p.ref_count, i64(0))
		if p.index == 0 {testing.expect(t, p.state == .Clean && p.written_bytes == 16)}
	}
	testing.expect_value(t, sets[0].lock, u32(0))
}

ai_unexpected_transfer :: proc(ctx: rawptr, data: rifle.IOUserData, buffer: []u8, offset: u64, file: rifle.RifleFile) -> rifle.RifleError {
	panic("unexpected I/O transfer in cache wait test")
}

ai_unexpected_sync :: proc(ctx: rawptr, data: rifle.IOUserData) -> rifle.RifleError {
	panic("unexpected sync in cache wait test")
}

// Storage for tests which construct page sets directly.
ai_cache_paths :: proc(c: ^$Cache/rifle.PageCache_Impl, storage: []u8) {
	c.pages_per_file = 4
	i := 0
	for &set in c.sets {
		for &p in set.pages {
			p.path_buffer = storage[i * 64:(i + 1) * 64]
			i += 1
		}
	}
}

@(test)
cache_page_file_paths :: proc(t: ^testing.T) {
	f: Fake_IO
	pc: Fake_PageCache
	durable_index: i64
	extra_require(t, rifle.cache_init(&pc, 64, 16, fake_io(&f), "/tmp/rifle/", 32, &durable_index) == nil)
	defer rifle.cache_delete(&pc)
	pc.record_size = 4
	data: [64]u8
	rifle.cache_write(&pc, data[:], 0, 16)
	for &p in pc.pages {
		testing.expect_value(t, p.file_id, p.index / 2)
		expected := p.file_id == 0 ? "/tmp/rifle/data_0.rfl" : "/tmp/rifle/data_1.rfl"
		testing.expect_value(t, string(p.path), expected)
		p.ref_count = 1
	}
	p := &pc.pages[0]
	p.ref_count = 0
	p.state = .Clean
	path_address := p.path
	rifle.cache_write(&pc, data[:16], 400 * 4, 4)
	testing.expect_value(t, p.file_id, i64(200))
	testing.expect_value(t, string(p.path), "/tmp/rifle/data_200.rfl")
	testing.expect(t, p.path == path_address)
	p.state = .Clean
	rifle.cache_write(&pc, data[:16], 8 * 4, 4)
	testing.expect_value(t, string(p.path), "/tmp/rifle/data_4.rfl")
	testing.expect(t, p.path == path_address)
	// Poll uses the file metadata and the offset within that file.
	p.index = 9
	rifle.cache_poll(&pc)
	found := false
	for r in f.requests {
		if raw_data(r.buffer) == raw_data(p.data) {
			found = true
			testing.expect_value(t, r.file.id, i64(4))
			testing.expect_value(t, string(r.file.path), "/tmp/rifle/data_4.rfl")
			testing.expect_value(t, r.offset, u64(16))
		}
	}
	testing.expect(t, found)
}

@(test)
cache_poll_releases_completion_locks :: proc(t: ^testing.T) {
	results := [2]i32{16, 8}
	for res in results {
		f: Fake_IO
		io := fake_io(&f)
		defer Fake_IO_Interface.deinit(io)
		pages: [8]rifle.Page
		sets: [2]rifle.Set(rifle.SET_ASSOC)
		for &set, i in sets {set.pages = pages[i * 4:(i + 1) * 4]}
		pages[4] = {index = 10, state = .Loading, ref_count = 1}
		pages[5] = {index = 12, state = .Flushing, written_bytes = 16}
		completions: [2]rifle.IOCompletion
		append(&f.completions,
			rifle.IOCompletion{user_data = {op = .READ, page_index = 4}, res = res},
			rifle.IOCompletion{user_data = {op = .WRITE, page_index = 5}, res = res})
		pc := Fake_PageCache{page_size = 16, pages = pages[:], sets = sets[:], io_state = io, io_completions = completions[:]}
		polled, err := rifle.cache_poll(&pc)
		testing.expect(t, polled && err == nil && pc.polling == 0)
		testing.expect(t, pages[4].state == (res == 16 ? .Clean : .Read_Pending))
		testing.expect(t, pages[5].state == (res == 16 ? .Clean : .Dirty))
		testing.expect_value(t, pages[4].ref_count, i64(1))
		for set in sets {testing.expect_value(t, set.lock, u32(0))}
	}
}

@(test)
cache_sync_updates_durable_index :: proc(t: ^testing.T) {
	f: Fake_IO
	io := fake_io(&f)
	defer Fake_IO_Interface.deinit(io)
	completions: [1]rifle.IOCompletion
	durable_index: i64 = -1
	pc := Fake_PageCache{io_state = io, io_completions = completions[:], durable_index = &durable_index}
	rifle.cache_sync(&pc, 0)
	rifle.cache_poll(&pc)
	testing.expect(t, pc.sync_in_progress && len(f.requests) == 1)
	rifle.cache_sync(&pc, 100)
	rifle.cache_poll(&pc)
	testing.expect(t, len(f.requests) == 1 && pc.sync_index == 0)
	testing.expect(t, durable_index == -1)
	fake_io_complete(&f, 0, 0)
	_, err := rifle.cache_poll(&pc)
	testing.expect(t, durable_index == 0 && err == nil && !pc.sync_in_progress)
	rifle.cache_poll(&pc)
	testing.expect(t, pc.sync_in_progress && pc.sync_index == 100)
	fake_io_complete(&f, 0, 0)
	_, err = rifle.cache_poll(&pc)
	testing.expect(t, durable_index == 100 && err == nil && !pc.sync_in_progress)
	rifle.cache_sync(&pc, 200)
	rifle.cache_poll(&pc)
	fake_io_complete(&f, 0, -1)
	rifle.cache_poll(&pc)
	testing.expect(t, durable_index == 100 && !pc.sync_in_progress)
}


AI_Flush_Wait_IO :: rifle.IO_Impl(AI_Flush_Wait_State, nil, nil, nil, nil, ai_unexpected_transfer, ai_unexpected_transfer, ai_unexpected_sync, nil, AI_Flush_Wait_poll)

AI_Flush_Wait_Cache :: rifle.PageCache_Impl(AI_Flush_Wait_IO)

AI_Flush_Wait_State :: struct {
	t:     ^testing.T,
	sets: []rifle.Set(rifle.SET_ASSOC),
	calls: int,
}

AI_Flush_Wait_poll :: proc(ctx: rawptr, completions: []rifle.IOCompletion) -> (u32, rifle.RifleError) {
	s := cast(^AI_Flush_Wait_State)ctx
	set := &s.sets[0]
	p := &set.pages[0]
	testing.expect_value(s.t, set.lock, u32(0))
	testing.expect_value(s.t, p.ref_count, i64(1))
	testing.expect_value(s.t, p.written_bytes, i64(4))
	testing.expect_value(s.t, p.data[4], u8(0))
	s.calls += 1
	if s.calls == 2 {p.state = .Clean}
	return 0, nil
}

AI_Read_Wait_IO :: rifle.IO_Impl(AI_Read_Wait_State, nil, nil, nil, nil, AI_Read_Wait_read, ai_unexpected_transfer, ai_unexpected_sync, nil, AI_Read_Wait_poll)

AI_Read_Wait_Cache :: rifle.PageCache_Impl(AI_Read_Wait_IO)

AI_Read_Wait_State :: struct {t: ^testing.T, sets: []rifle.Set(rifle.SET_ASSOC), output: []u8, calls: int}

AI_Read_Wait_poll :: proc(ctx: rawptr, completions: []rifle.IOCompletion) -> (u32, rifle.RifleError) {
	s := cast(^AI_Read_Wait_State)ctx
	set := &s.sets[0]
	testing.expect_value(s.t, set.lock, u32(0))
	for b in s.output {testing.expect_value(s.t, b, u8(0xee))}
	s.calls += 1
	testing.expect(s.t, s.calls <= 2)
	for &p in set.pages {
		if p.index != 0 {continue}
		testing.expect_value(s.t, p.ref_count, i64(1))
		if s.calls == 1 {
			testing.expect_value(s.t, p.state, rifle.PageState.Loading)
			p.state = .Loading
		} else {
			testing.expect_value(s.t, p.state, rifle.PageState.Loading)
			for &b, i in p.data {b = u8(i)}
			p.written_bytes = 16
			p.state = .Clean
		}
	}
	return 0, nil
}

AI_Read_Wait_read :: proc(ctx: rawptr, data: rifle.IOUserData, buffer: []u8, offset: u64, file: rifle.RifleFile) -> rifle.RifleError {
	s := cast(^AI_Read_Wait_State)ctx
	testing.expect_value(s.t, s.sets[0].lock, u32(1))
	return nil
}
