package test

import "core:testing"
import "core:sync"
import "core:thread"
import "core:time"
import rifle "rifle:rifle"

@(test)
cache_propagates_io_initialization_failure :: proc(t: ^testing.T) {
	f: Fake_IO
	io := fake_io(&f)
	io.init = proc(ctx: rawptr, buffer: []u8) -> rifle.RifleError {return .GenericError}
	pc := new(rifle.PageCache)
	durable: i64
	err := rifle.cache_init(pc, 256, 64, io, "/tmp/rifle-contract", 256, 8, &durable)
	defer rifle.cache_deinit(pc)
	testing.expect(t, err == .GenericError)
}

@(test)
cache_propagates_io_poll_failure :: proc(t: ^testing.T) {
	f: Fake_IO
	pc := new(rifle.PageCache)
	durable: i64
	extra_require(t, rifle.cache_init(pc, 256, 64, fake_io(&f), "/tmp/rifle-contract", 256, 8, &durable) == nil)
	defer rifle.cache_deinit(pc)
	f.poll_error = .FileOperationError
	_, err := rifle.cache_poll(pc)
	testing.expect(t, err == .FileOperationError)
	testing.expect_value(t, pc.polling, u32(0))
}

@(test)
cache_flushes_only_full_pages_and_retries_failed_writes :: proc(t: ^testing.T) {
	f: Fake_IO
	pc := new(rifle.PageCache)
	durable: i64
	extra_require(t, rifle.cache_init(pc, 256, 64, fake_io(&f), "/tmp/rifle-contract", 256, 8, &durable) == nil)
	defer rifle.cache_deinit(pc)
	data: [64]u8
	for &b, i in data {b = u8(i)}
	rifle.cache_write(pc, data[:32], 0, 4)
	rifle.cache_poll(pc)
	testing.expect_value(t, len(f.requests), 0)
	rifle.cache_write(pc, data[32:], 4, 4)
	f.next_error = .FileNotReady
	rifle.cache_poll(pc)
	testing.expect_value(t, len(f.requests), 0)
	rifle.cache_poll(pc)
	extra_require(t, len(f.requests) == 1)
	slot := f.requests[0].user_data.page_index
	results := []i32{32, -5}
	for res in results {
		fake_io_complete(&f, 0, res)
		rifle.cache_poll(pc)
		testing.expect(t, pc.pages[slot].state == .Dirty)
		rifle.cache_poll(pc)
		extra_require(t, len(f.requests) == 1)
		testing.expect_value(t, f.requests[0].user_data.page_index, slot)
		for b, i in f.requests[0].buffer {testing.expect_value(t, b, data[i])}
	}
	fake_io_complete(&f, 0, 64)
	rifle.cache_poll(pc)
	testing.expect(t, pc.pages[slot].state == .Clean)
	testing.expect_value(t, durable, i64(0)) // Write completion is not sync completion.
}

@(test)
cache_retries_short_reads_before_marking_clean :: proc(t: ^testing.T) {
	f: Fake_IO
	pc := new(rifle.PageCache)
	durable: i64
	extra_require(t, rifle.cache_init(pc, 256, 64, fake_io(&f), "/tmp/rifle-contract", 256, 8, &durable) == nil)
	defer rifle.cache_deinit(pc)
	p := &pc.pages[0]
	p.index, p.state, p.ref_count = 0, .Read_Pending, 1
	rifle.cache_poll(pc)
	extra_require(t, len(f.requests) == 1)
	data: [64]u8
	for &b, i in data {b = u8(i + 1)}
	fake_io_complete(&f, 0, 16, data[:])
	rifle.cache_poll(pc)
	testing.expect(t, p.state == .Read_Pending && p.written_bytes == 0)
	rifle.cache_poll(pc)
	extra_require(t, len(f.requests) == 1)
	fake_io_complete(&f, 0, 64, data[:])
	rifle.cache_poll(pc)
	testing.expect(t, p.state == .Clean && p.written_bytes == 64 && p.ref_count == 1)
	for b, i in p.data {testing.expect_value(t, b, data[i])}
}

@(test)
cache_sync_does_not_cover_rejected_writes :: proc(t: ^testing.T) {
	f: Fake_IO
	pc := new(rifle.PageCache)
	durable: i64
	extra_require(t, rifle.cache_init(pc, 256, 64, fake_io(&f), "/tmp/rifle-contract", 256, 8, &durable) == nil)
	defer rifle.cache_deinit(pc)
	data: [64]u8
	rifle.cache_write(pc, data[:], 0, 8)
	rifle.cache_sync(pc, 8)
	f.next_error = .FileNotReady
	rifle.cache_poll(pc)
	// Complete only a sync, if issued. The target's write has not been accepted.
	for request, i in f.requests {
		if request.user_data.op == .SYNC {
			fake_io_complete(&f, i, 0)
			break
		}
	}
	rifle.cache_poll(pc)
	testing.expect_value(t, durable, i64(0))
}

@(test)
cache_durable_index_never_regresses :: proc(t: ^testing.T) {
	f: Fake_IO
	pc := new(rifle.PageCache)
	durable: i64
	extra_require(t, rifle.cache_init(pc, 256, 64, fake_io(&f), "/tmp/rifle-contract", 256, 8, &durable) == nil)
	defer rifle.cache_deinit(pc)
	data: [64]u8
	rifle.cache_write(pc, data[:], 0, 8)
	rifle.cache_poll(pc)
	extra_require(t, len(f.requests) == 1)
	fake_io_complete(&f, 0, 64)
	rifle.cache_poll(pc)
	// A delayed caller can request an older target after a newer one completed.
	targets := []i64{8, 4}
	for target in targets {
		rifle.cache_sync(pc, target)
		rifle.cache_poll(pc)
		if len(f.requests) > 0 {
			extra_require(t, f.requests[0].user_data.op == .SYNC)
			fake_io_complete(&f, 0, 0)
			rifle.cache_poll(pc)
		}
		testing.expect_value(t, durable, i64(8))
	}
}

Cache_Copy_Worker :: struct {
	cache: ^rifle.PageCache,
	id: int,
	barrier: ^sync.Barrier,
	done: ^i64,
}

cache_copy_worker :: proc(t: ^thread.Thread) {
	w := cast(^Cache_Copy_Worker)t.data
	sync.barrier_wait(w.barrier)
	for page in 0 ..< 128 {
		start := i64(page * 8 + w.id * 2)
		data := [2]i64{start + 1, start + 2}
		rifle.cache_write(w.cache, (cast([^]u8)raw_data(data[:]))[:16], start, 2)
	}
	sync.atomic_add(w.done, 1)
}

@(test)
cache_concurrent_page_writers_with_caller_polling :: proc(t: ^testing.T) {
	testing.set_fail_timeout(t, 10 * time.Second)
	f: Fake_IO
	pc := new(rifle.PageCache)
	durable: i64
	extra_require(t, rifle.cache_init(pc, 128 * 64, 64, fake_io(&f), "/tmp/rifle-contract", 256, 8, &durable) == nil)
	defer rifle.cache_deinit(pc)
	barrier: sync.Barrier
	sync.barrier_init(&barrier, 5)
	done: i64
	workers: [4]Cache_Copy_Worker
	threads: [4]^thread.Thread
	for &w, i in workers {
		w = {cache = pc, id = i, barrier = &barrier, done = &done}
		threads[i] = thread.create(cache_copy_worker)
		threads[i].data = &w
		thread.start(threads[i])
	}
	sync.barrier_wait(&barrier)
	for sync.atomic_load(&done) < 4 {rifle.cache_poll(pc)}
	for worker in threads {
		thread.join(worker)
		thread.destroy(worker)
	}
	rifle.cache_poll(pc)
	extra_require(t, len(f.requests) == 128)
	seen: [128]bool
	for request in f.requests {
		extra_require(t, request.user_data.op == .WRITE && len(request.buffer) == 64)
		page := request.file.id * 4 + i64(request.offset / 64)
		extra_require(t, page >= 0 && page < 128)
		testing.expect(t, !seen[page])
		seen[page] = true
		values := (cast([^]i64)raw_data(request.buffer))[:8]
		for value, i in values {extra_require(t, value == page * 8 + i64(i) + 1)}
	}
	// Deliberately complete in reverse submission order.
	for len(f.requests) > 0 {fake_io_complete(&f, len(f.requests) - 1, 64)}
	rifle.cache_poll(pc)
	for p in pc.pages {
		testing.expect(t, p.state == .Clean && p.written_bytes == 64 && p.ref_count == 0)
	}
	testing.expect_value(t, durable, i64(0))
}
