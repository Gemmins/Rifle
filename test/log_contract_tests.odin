package test

import "core:testing"
import rifle "rifle:rifle"

Log_Cache_Spy :: struct {
	ctx: rawptr,
	calls: int,
	index, count: i64,
}

// Keep the spy in the test context so a bad forwarded pointer can be inspected
// without dereferencing it and crashing the test.
@(test)
log_poll_forwards_cache_context_and_error :: proc(t: ^testing.T) {
	spy: Log_Cache_Spy
	context.user_ptr = &spy
	l: rifle.Log
	l.cache.data = &spy
	l.cache.poll = proc(ctx: rawptr) -> (bool, rifle.RifleError) {
		s := cast(^Log_Cache_Spy)context.user_ptr
		s.ctx = ctx
		s.calls += 1
		return true, .FileOperationError
	}
	progress, err := rifle.log_poll(&l)
	testing.expect(t, progress && err == .FileOperationError)
	testing.expect_value(t, spy.calls, 1)
	testing.expect(t, spy.ctx == l.cache.data)
}

@(test)
log_sync_forwards_visible_target_and_context :: proc(t: ^testing.T) {
	spy: Log_Cache_Spy
	context.user_ptr = &spy
	l: rifle.Log
	l.commited_index.value = 24
	l.visible_index.value = 17
	l.durable_index.value = 8
	l.cache.data = &spy
	l.cache.sync = proc(ctx: rawptr, target: i64) {
		s := cast(^Log_Cache_Spy)context.user_ptr
		s.ctx = ctx
		s.index = target
		s.calls += 1
	}
	testing.expect_value(t, rifle.log_sync(&l), i64(17))
	testing.expect_value(t, spy.calls, 1)
	testing.expect_value(t, spy.index, i64(17))
	testing.expect(t, spy.ctx == l.cache.data)
	testing.expect_value(t, l.durable_index.value, i64(8))
}

@(test)
log_read_respects_visible_and_trailing_bounds :: proc(t: ^testing.T) {
	spy: Log_Cache_Spy
	l: rifle.Log
	l.trailing_index.value = 5
	l.visible_index.value = 10
	l.commited_index.value = 20
	l.cache.data = &spy
	l.cache.read = proc(ctx: rawptr, buffer: []u8, index, count: i64) {
		s := cast(^Log_Cache_Spy)ctx
		s.calls += 1
		s.index, s.count = index, count
	}
	cases := [?]struct {index, count: i64, valid: bool}{
		{5, 1, true}, {5, 5, true}, {9, 1, true}, {10, 0, true},
		{4, 1, false}, {10, 1, false}, {8, 3, false},
	}
	for tc in cases {
		spy.calls = 0
		err := rifle.log_read(&l, nil, tc.index, tc.count)
		testing.expect(t, (err == nil) == tc.valid)
		testing.expect_value(t, spy.calls, tc.valid ? 1 : 0)
		if tc.valid {
			testing.expect(t, spy.index == tc.index && spy.count == tc.count)
		}
	}
}

@(test)
log_read_rejects_negative_and_overflowing_ranges :: proc(t: ^testing.T) {
	spy: Log_Cache_Spy
	l: rifle.Log
	l.visible_index.value = 10
	l.cache.data = &spy
	l.cache.read = proc(ctx: rawptr, buffer: []u8, index, count: i64) {
		(cast(^Log_Cache_Spy)ctx).calls += 1
	}
	cases := [?]struct {index, count: i64}{{0, -1}, {max(i64) - 1, 4}, {-1, 1}}
	for tc in cases {
		spy.calls = 0
		testing.expect(t, rifle.log_read(&l, nil, tc.index, tc.count) != nil)
		testing.expect_value(t, spy.calls, 0)
	}
}

@(test)
log_drop_advances_only_within_visible_range :: proc(t: ^testing.T) {
	spy: Log_Cache_Spy
	l: rifle.Log
	l.visible_index.value = 10
	l.cache.data = &spy
	l.cache.drop = proc(ctx: rawptr, index: i64) {
		s := cast(^Log_Cache_Spy)ctx
		s.calls += 1
		s.index = index
	}
	testing.expect(t, rifle.log_drop(&l, 11) == .IndexOutOfBoundsError)
	testing.expect_value(t, spy.calls, 0)
	testing.expect(t, rifle.log_drop(&l, 5) == nil)
	testing.expect(t, spy.index == 5 && l.trailing_index.value == 5)
	testing.expect(t, rifle.log_drop(&l, 4) != nil)
	testing.expect_value(t, spy.calls, 1)
	testing.expect_value(t, l.visible_index.value, i64(10))
}
