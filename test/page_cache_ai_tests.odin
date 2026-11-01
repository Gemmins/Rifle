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
				page_start := i64(index) * 16
				write_start := tc.start * tc.record_size
				write_end := (tc.start + tc.count) * tc.record_size
				touched := tc.count > 0 && page_start < write_end && page_start + 16 > write_start
				p = {
					data  = backing[index * 16:(index + 1) * 16],
					index = i64(index),
					state = touched ? .Dirty : .Clean,
					// A write appends after any already-copied prefix; clean pages are full.
					written_bytes = touched ? max(write_start - page_start, 0) : 16,
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
			expected_bytes := touched ? min(begin + n - p.index * 16, 16) : 16
			testing.expect_value(t, p.written_bytes, expected_bytes)
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
		pages[0].state = .Dirty
		pages[0].written_bytes = 4 // Incomplete writes remain dirty until the page is full.
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
		testing.expect(t, pages[0].index == 0 && pages[0].written_bytes == 4 && pages[0].state == .Dirty)
		testing.expect(t, pages[1].index == 1 && pages[1].ref_count == 1)
		testing.expect(t, pages[2].index == 2 && pages[2].state == .Dirty)
		testing.expect(t, pages[3].index == 4 && pages[3].written_bytes == 4)
		rifle.cache_write(&pc, data[:12], 17, 3)
		testing.expect(t, pages[3].written_bytes == 16 && pages[3].ref_count == 0)
	}
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
	completions: [1]rifle.IOCompletion
	pc := rifle.PageCache{page_size = 16, num_pages = 4, record_size = 4, pages = pages[:], sets = sets[:], io_completions = completions[:]}
	path_storage: [512]u8
	ai_cache_paths(&pc, path_storage[:])
	output := [4]u8{0xee, 0xee, 0xee, 0xee}
	Poll_State :: struct {t: ^testing.T, cache: ^rifle.PageCache, output: []u8, calls: int, token: rifle.IOUserData}
	state := Poll_State{t = t, cache = &pc, output = output[:]}
	pc.io.data = &state
	pc.io.read_at = proc(ctx: rawptr, data: rifle.IOUserData, buffer: []u8, offset: u64, file: rifle.RifleFile) -> rifle.RifleError {
		s := cast(^Poll_State)ctx
		testing.expect_value(s.t, s.cache.sets[0].lock, u32(1))
		s.token = data
		return nil
	}
	// Simulate the delayed completion.
	pc.io.poll = proc(ctx: rawptr, completions: []rifle.IOCompletion) -> (u32, rifle.RifleError) {
		s := cast(^Poll_State)ctx
		set := &s.cache.sets[0]
		testing.expect_value(s.t, set.lock, u32(0))
		for b in s.output {testing.expect_value(s.t, b, u8(0xee))}
		s.calls += 1
		testing.expect(s.t, s.calls <= 2)
		for &p in set.pages {
			if p.index != 0 {continue}
			testing.expect_value(s.t, p.ref_count, i64(1))
			testing.expect_value(s.t, p.state, rifle.PageState.Loading)
			if s.calls == 2 {
				for &b, i in p.data {b = u8(i)}
				completions[0] = {user_data = s.token, res = 16}
				return 1, nil
			}
		}
		return 0, nil
	}
	rifle.cache_read(&pc, output[:], 1, 1)
	testing.expect_value(t, state.calls, 2)
	for b, i in output {testing.expect_value(t, b, u8(i + 4))}
	for p in pages {
		testing.expect_value(t, p.ref_count, i64(0))
		if p.index == 0 {testing.expect(t, p.state == .Clean && p.written_bytes == 16)}
	}
	testing.expect_value(t, sets[0].lock, u32(0))
}

// Storage for tests which construct page sets directly.
ai_cache_paths :: proc(c: ^rifle.PageCache, storage: []u8) {
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
	pc := new(rifle.PageCache)
	durable_index: i64
	extra_require(t, rifle.cache_init(pc, 64, 16, fake_io(&f), "/tmp/rifle/", 32, 4, &durable_index) == nil)
	defer rifle.cache_deinit(pc)
	data: [64]u8
	rifle.cache_write(pc, data[:], 0, 16)
	rifle.cache_poll(pc)
	for len(f.requests) > 0 {fake_io_complete(&f, 0, 16)}
	rifle.cache_poll(pc)
	for &p in pc.pages {
		testing.expect_value(t, p.file_id, p.index / 2)
		expected := p.file_id == 0 ? "/tmp/rifle/data_0.rfl" : "/tmp/rifle/data_1.rfl"
		testing.expect_value(t, string(p.path), expected)
		p.ref_count = 1
	}
	p := &pc.pages[0]
	p.ref_count = 0
	path_address := p.path
	rifle.cache_write(pc, data[:16], 400 * 4, 4)
	testing.expect_value(t, p.file_id, i64(200))
	testing.expect_value(t, string(p.path), "/tmp/rifle/data_200.rfl")
	testing.expect(t, p.path == path_address)
	rifle.cache_poll(pc)
	fake_io_complete(&f, 0, 16)
	rifle.cache_poll(pc)
	rifle.cache_write(pc, data[:16], 9 * 4, 4)
	testing.expect_value(t, string(p.path), "/tmp/rifle/data_4.rfl")
	testing.expect(t, p.path == path_address)
	// Poll uses the file metadata and the offset within that file.
	rifle.cache_poll(pc)
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
	results := [4]i32{16, 8, 0, -5}
	for res in results {
		f: Fake_IO
		io := fake_io(&f)
		defer io.deinit(io.data)
		pages: [8]rifle.Page
		sets: [2]rifle.Set(rifle.SET_ASSOC)
		for &p in pages {p.index = -1}
		for &set, i in sets {
			set.pages = pages[i * 4:(i + 1) * 4]
			set.lru = rifle.lru_new()
		}
		pages[4] = {index = 11, state = .Loading, ref_count = 1}
		pages[5] = {index = 13, state = .Flushing, written_bytes = 16}
		completions: [2]rifle.IOCompletion
		append(&f.completions,
			rifle.IOCompletion{user_data = {op = .READ, page_index = 4}, res = res},
			rifle.IOCompletion{user_data = {op = .WRITE, page_index = 5}, res = res})
		pc := rifle.PageCache{page_size = 16, pages = pages[:], sets = sets[:], io = io, io_completions = completions[:]}
		polled, err := rifle.cache_poll(&pc)
		testing.expect(t, polled && err == nil && pc.polling == 0)
		testing.expect(t, pages[4].state == (res == 16 ? .Clean : .Read_Pending))
		testing.expect(t, pages[5].state == (res == 16 ? .Clean : .Dirty))
		testing.expect_value(t, pages[4].ref_count, i64(1))
		expected_lru := res == 16 ? rifle.lru_update(rifle.lru_new(), 1) : rifle.lru_new()
		testing.expect_value(t, sets[1].lru, expected_lru)
		for set in sets {testing.expect_value(t, set.lock, u32(0))}
	}
}

@(test)
cache_sync_updates_durable_index :: proc(t: ^testing.T) {
	f: Fake_IO
	io := fake_io(&f)
	defer io.deinit(io.data)
	completions: [1]rifle.IOCompletion
	durable_index: i64 = -1
	pc := rifle.PageCache{io = io, io_completions = completions[:], durable_index = &durable_index}
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
