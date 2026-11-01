package test

import rifle "rifle:rifle"
import "core:sync"
import "core:testing"
import "core:thread"
import "core:time"

@(test)
log_write_completion_ring_wrap :: proc(t: ^testing.T) {
	l: rifle.Log
	l.commit_ring = make(type_of(l.commit_ring), 4)
	defer delete(l.commit_ring)
	l.commit_mask = 3
	for &slot in l.commit_ring {
		slot.value = -1
	}
	l.cache.write = proc(ctx: rawptr, data: []u8, start: i64, count: i64) {}

	// Each call crosses the ring boundary, exercising repeated capacity checks.
	starts := []i64{0, 11}
	for start in starts {
		index, err := rifle.log_write(&l, nil, 11)
		testing.expect(t, err == nil)
		testing.expect(t, index == start)
		testing.expect(t, sync.atomic_load(&l.visible_index.value) == start + 11)
		for record in start + 7 ..< start + 11 {
			testing.expect(t, l.commit_ring[u64(record) & l.commit_mask].value == record)
		}
	}
}

Log_Write_Gate :: struct {
	entered: sync.Sema,
	release: sync.Sema,
}

Log_Write_Worker :: struct {
	log: ^rifle.Log,
	count: i64,
	index: i64,
	err: rifle.RifleError,
}

log_write_worker :: proc(t: ^thread.Thread) {
	w := cast(^Log_Write_Worker)t.data
	w.index, w.err = rifle.log_write(w.log, nil, w.count)
}

@(test)
log_write_waits_for_contiguous_completion :: proc(t: ^testing.T) {
	l: rifle.Log
	l.commit_ring = make(type_of(l.commit_ring), 4)
	defer delete(l.commit_ring)
	l.commit_mask = 3
	for &slot in l.commit_ring {slot.value = -1}
	gate: Log_Write_Gate
	l.cache.data = &gate
	l.cache.write = proc(ctx: rawptr, data: []u8, start: i64, count: i64) {
		if start == 0 {
			gate := cast(^Log_Write_Gate)ctx
			sync.sema_post(&gate.entered)
			sync.sema_wait(&gate.release)
		}
	}
	w := Log_Write_Worker{log = &l, count = 1}
	worker := thread.create(log_write_worker)
	worker.data = &w
	thread.start(worker)
	defer thread.destroy(worker)
	if !testing.expect(t, sync.sema_wait_with_timeout(&gate.entered, 5 * time.Second)) {
		sync.sema_post(&gate.release)
		thread.join(worker)
		return
	}
	// Later records finish while record zero is still inside the cache write.
	index, err := rifle.log_write(&l, nil, 2)
	testing.expect(t, err == nil)
	testing.expect_value(t, index, i64(1))
	testing.expect_value(t, sync.atomic_load(&l.visible_index.value), i64(0))
	testing.expect_value(t, sync.atomic_load(&l.commit_ring[0].value), i64(-1))
	testing.expect_value(t, sync.atomic_load(&l.commit_ring[1].value), i64(1))
	testing.expect_value(t, sync.atomic_load(&l.commit_ring[2].value), i64(2))
	sync.sema_post(&gate.release)
	thread.join(worker)
	testing.expect(t, w.err == nil)
	testing.expect_value(t, w.index, i64(0))
	testing.expect_value(t, sync.atomic_load(&l.visible_index.value), i64(3))
	// An empty append reserves nothing and preserves the visible prefix.
	index, err = rifle.log_write(&l, nil, 0)
	testing.expect(t, err == nil)
	testing.expect_value(t, index, i64(3))
	testing.expect_value(t, l.commited_index.value, i64(3))
	testing.expect_value(t, l.visible_index.value, i64(3))
}

@(test)
log_write_concurrent_batches :: proc(t: ^testing.T) {
	l: rifle.Log
	l.commit_ring = make(type_of(l.commit_ring), 4)
	defer delete(l.commit_ring)
	l.commit_mask = 3
	for &slot in l.commit_ring {slot.value = -1}
	barrier: sync.Barrier
	sync.barrier_init(&barrier, 8)
	l.cache.data = &barrier
	l.cache.write = proc(ctx: rawptr, data: []u8, start: i64, count: i64) {
		// All ranges are reserved before any writer starts publishing completions.
		sync.barrier_wait(cast(^sync.Barrier)ctx)
	}
	workers: [8]Log_Write_Worker
	threads: [8]^thread.Thread
	for &w, i in workers {
		w.log = &l
		w.count = 17
		threads[i] = thread.create(log_write_worker)
		threads[i].data = &w
		thread.start(threads[i])
	}
	for worker in threads {
		thread.join(worker)
		thread.destroy(worker)
	}
	seen: [8]bool
	for w in workers {
		testing.expect(t, w.err == nil)
		if testing.expect(t, w.index >= 0 && w.index < 136 && w.index % 17 == 0) {
			testing.expect(t, !seen[w.index / 17])
			seen[w.index / 17] = true
		}
	}
	testing.expect_value(t, l.commited_index.value, i64(136))
	testing.expect_value(t, l.visible_index.value, i64(136))
	for record in 132 ..< 136 {
		testing.expect_value(t, l.commit_ring[u64(record) & l.commit_mask].value, i64(record))
	}
}
