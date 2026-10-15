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
	pc := rifle.PageCache {
		page_size   = 16,
		num_pages   = 4,
		record_size = 4,
		sets        = sets[:],
	}
	Poll_State :: struct {
		t:     ^testing.T,
		cache: ^rifle.PageCache,
		calls: int,
	}
	state := Poll_State {
		t     = t,
		cache = &pc,
	}
	pc.io.data = &state
	pc.io.poll = proc(ctx: rawptr, completions: []rifle.IOCompletion) -> (u32, rifle.RifleError) {
		s := cast(^Poll_State)ctx
		set := &s.cache.sets[0]
		p := &set.pages[0]
		testing.expect_value(s.t, set.lock, u32(0))
		testing.expect_value(s.t, p.ref_count, i64(1))
		testing.expect_value(s.t, p.written_bytes, i64(4))
		testing.expect_value(s.t, p.data[4], u8(0))
		s.calls += 1
		if s.calls == 2 {p.state = .Clean}
		return 0, nil
	}
	data := [4]u8{1, 2, 3, 4}
	rifle.cache_write(&pc, data[:], 1, 1)
	testing.expect_value(t, state.calls, 2)
	testing.expect(t, pages[0].state == .Dirty && pages[0].written_bytes == 8)
	testing.expect_value(t, pages[0].ref_count, i64(0))
	for b, i in data {testing.expect_value(t, backing[4 + i], b)}
}
