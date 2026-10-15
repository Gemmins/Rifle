package test

import rifle "rifle:rifle"
import "core:testing"
import "core:thread"

CAPACITY     :: 4
BLOCK_SIZE   :: 16
THREAD_COUNT :: 4

make_cache :: proc() -> (c: rifle.BlockCache) {
	rifle.block_cache_init(&c, CAPACITY, BLOCK_SIZE)
	return
}

// Scans entries for a matching key without acquiring any locks.
// Only safe to call from a single thread when no concurrent modifications are in flight.
cache_key_exists :: proc(c: ^rifle.BlockCache, key: i64) -> bool {
	for &e in c.entries {
		if e.key == key do return true
	}
	return false
}

// ─── Lifecycle ────────────────────────────────────────────────────────────────

@(test)
cache_create_destroy :: proc(t: ^testing.T) {
	c: rifle.BlockCache
	err := rifle.block_cache_init(&c, CAPACITY, BLOCK_SIZE)
	testing.expect(t, err == nil)
	rifle.block_cache_destroy(&c)
}

// ─── Get / hit / miss ─────────────────────────────────────────────────────────

// key=0 is a valid block index.  A fresh cache should report it as a miss, not
// a spurious hit caused by zero-initialised entry.key.  This currently fails:
// all entries start with key=0 so the hit check fires immediately.  The fix is
// to initialise entry.key to a sentinel (e.g. -1) so key=0 goes through the
// miss path like any other cold key.
@(test)
cache_key_zero_is_miss_on_fresh_cache :: proc(t: ^testing.T) {
	c := make_cache()
	defer rifle.block_cache_destroy(&c)

	_, hit := rifle.block_cache_get(&c, 0)
	defer rifle.block_cache_release(&c, 0)

	testing.expect(t, !hit)
}

@(test)
cache_get_miss_returns_slot :: proc(t: ^testing.T) {
	c := make_cache()
	defer rifle.block_cache_destroy(&c)

	block, hit := rifle.block_cache_get(&c, 1)
	defer rifle.block_cache_release(&c, 1)

	testing.expect(t, !hit)
	testing.expect(t, block != nil)
	testing.expect(t, block.data != nil)
}

@(test)
cache_get_hit_returns_same_block :: proc(t: ^testing.T) {
	c := make_cache()
	defer rifle.block_cache_destroy(&c)

	block1, _ := rifle.block_cache_get(&c, 1)
	block1.data[0] = 42

	// Second get for the same key: both shared locks must be released.
	block2, hit := rifle.block_cache_get(&c, 1)
	testing.expect(t, hit)
	testing.expect(t, block1 == block2)
	testing.expect(t, block2.data[0] == 42)

	rifle.block_cache_release(&c, 1)
	rifle.block_cache_release(&c, 1)
}

// ─── Backing allocation ───────────────────────────────────────────────────────

@(test)
cache_backing_data_is_preallocated :: proc(t: ^testing.T) {
	c := make_cache()
	defer rifle.block_cache_destroy(&c)

	for i in 0 ..< CAPACITY {
		testing.expect(t, c.blocks[i].data != nil)
		testing.expect(t, len(c.blocks[i].data) == BLOCK_SIZE)
	}
}

// ─── Capacity / eviction ──────────────────────────────────────────────────────

@(test)
cache_fill_to_capacity_no_eviction :: proc(t: ^testing.T) {
	c := make_cache()
	defer rifle.block_cache_destroy(&c)

	// Use keys 1..CAPACITY to avoid the zero-initialised key=0 ambiguity.
	for i in 1 ..< CAPACITY + 1 {
		_, _ = rifle.block_cache_get(&c, cast(i64)i)
		rifle.block_cache_release(&c, cast(i64)i)
	}

	for i in 1 ..< CAPACITY + 1 {
		testing.expect(t, cache_key_exists(&c, cast(i64)i))
	}
}

@(test)
cache_eviction_evicts_lru_entry :: proc(t: ^testing.T) {
	c := make_cache()
	defer rifle.block_cache_destroy(&c)

	for i in 1 ..< CAPACITY + 1 {
		_, _ = rifle.block_cache_get(&c, cast(i64)i)
		rifle.block_cache_release(&c, cast(i64)i)
	}

	// One more key forces eviction of the oldest (smallest key value).
	_, _ = rifle.block_cache_get(&c, CAPACITY + 1)
	rifle.block_cache_release(&c, CAPACITY + 1)

	testing.expect(t, !cache_key_exists(&c, 1))
	testing.expect(t, cache_key_exists(&c, CAPACITY + 1))
}

@(test)
cache_eviction_reuses_slot_pointer :: proc(t: ^testing.T) {
	c := make_cache()
	defer rifle.block_cache_destroy(&c)

	// Capture the block pointer for key 1, then release so it can be evicted later.
	first, _ := rifle.block_cache_get(&c, 1)
	evicted_block := first
	rifle.block_cache_release(&c, 1)

	for i in 2 ..< CAPACITY + 1 {
		_, _ = rifle.block_cache_get(&c, cast(i64)i)
		rifle.block_cache_release(&c, cast(i64)i)
	}

	// All slots are full; key 1 is the oldest so its entry is claimed for the new key.
	reused, _ := rifle.block_cache_get(&c, CAPACITY + 1)
	defer rifle.block_cache_release(&c, CAPACITY + 1)

	testing.expect(t, reused == evicted_block)
}

// ─── Thread safety ────────────────────────────────────────────────────────────

Thread_Work :: struct {
	cache:  ^rifle.BlockCache,
	key:    i64,
	result: ^rifle.Block,
}

get_and_release_worker :: proc(data: rawptr) {
	w := cast(^Thread_Work)data
	block, _ := rifle.block_cache_get(w.cache, w.key)
	w.result = block
	rifle.block_cache_release(w.cache, w.key)
}

// THREAD_COUNT threads each claim a distinct key that maps to a different cache
// set, so there is no eviction pressure — verifies concurrent misses don't race.
@(test)
cache_concurrent_distinct_keys :: proc(t: ^testing.T) {
	c: rifle.BlockCache
	rifle.block_cache_init(&c, 16, BLOCK_SIZE)
	defer rifle.block_cache_destroy(&c)

	work:    [THREAD_COUNT]Thread_Work
	threads: [THREAD_COUNT]^thread.Thread

	for i in 0 ..< THREAD_COUNT {
		work[i] = {cache = &c, key = cast(i64)(i + 1)}
		threads[i] = thread.create_and_start_with_data(&work[i], get_and_release_worker)
	}
	for i in 0 ..< THREAD_COUNT {
		thread.join(threads[i])
		thread.destroy(threads[i])
	}

	for i in 0 ..< THREAD_COUNT {
		testing.expect(t, work[i].result != nil)
		testing.expect(t, cache_key_exists(&c, cast(i64)(i + 1)))
	}
}

// THREAD_COUNT threads all get the same pre-populated key concurrently — verifies
// that concurrent shared locks on the hit path return the same block pointer.
@(test)
cache_concurrent_same_key :: proc(t: ^testing.T) {
	c: rifle.BlockCache
	rifle.block_cache_init(&c, 16, BLOCK_SIZE)
	defer rifle.block_cache_destroy(&c)

	prime, _ := rifle.block_cache_get(&c, 1)
	rifle.block_cache_release(&c, 1)

	work:    [THREAD_COUNT]Thread_Work
	threads: [THREAD_COUNT]^thread.Thread

	for i in 0 ..< THREAD_COUNT {
		work[i] = {cache = &c, key = 1}
		threads[i] = thread.create_and_start_with_data(&work[i], get_and_release_worker)
	}
	for i in 0 ..< THREAD_COUNT {
		thread.join(threads[i])
		thread.destroy(threads[i])
	}

	for i in 0 ..< THREAD_COUNT {
		testing.expect(t, work[i].result == prime)
	}
}

Stress_Work :: struct {
	cache: ^rifle.BlockCache,
	key:   i64,
	iters: int,
}

stress_worker :: proc(data: rawptr) {
	d := cast(^Stress_Work)data
	for _ in 0 ..< d.iters {
		block, _ := rifle.block_cache_get(d.cache, d.key)
		_ = block.data[0]
		rifle.block_cache_release(d.cache, d.key)
	}
}

// ─── Adversarial thread safety ────────────────────────────────────────────────
//
// The following tests probe specific race conditions in the cache implementation.
// Some are expected to fail or hang on the current code; they exist to make the
// bugs visible and to act as regression guards once fixes land.

// ─── Basic stress (should pass) ───────────────────────────────────────────────

// THREAD_COUNT threads hammer get/release on the same key — primarily a
// deadlock and corruption detector under high contention.
@(test)
cache_concurrent_get_release_stress :: proc(t: ^testing.T) {
	c: rifle.BlockCache
	rifle.block_cache_init(&c, 16, BLOCK_SIZE)
	defer rifle.block_cache_destroy(&c)

	data:    [THREAD_COUNT]Stress_Work
	threads: [THREAD_COUNT]^thread.Thread

	for i in 0 ..< THREAD_COUNT {
		data[i] = {cache = &c, key = 1, iters = 1_000}
		threads[i] = thread.create_and_start_with_data(&data[i], stress_worker)
	}
	for i in 0 ..< THREAD_COUNT {
		thread.join(threads[i])
		thread.destroy(threads[i])
	}

	testing.expect(t, cache_key_exists(&c, 1))
}

// ─── Double-claim race ────────────────────────────────────────────────────────
//
// When two threads simultaneously miss on the same cold key, both fall through
// to the eviction path.  Thread A gets exclusive on entry[0]; thread B, finding
// entry[0] locked, tries the remaining entries and claims one of them — also
// with key=1.  Now two entries carry the same key.  block_cache_release scans
// linearly and unlocks whichever it finds first; the other entry keeps its
// shared lock forever.  The next eviction that needs to write-lock that entry
// will block indefinitely.
//
// The two tests below probe this from different angles.  Both are likely to
// fail on the current code once true parallelism occurs.

// All threads receive the same block pointer for the same key.  A double-claim
// gives different threads different pointers because they claimed different
// entries.
@(test)
cache_concurrent_cold_same_key_consistent_pointer :: proc(t: ^testing.T) {
	c: rifle.BlockCache
	rifle.block_cache_init(&c, 16, BLOCK_SIZE)
	defer rifle.block_cache_destroy(&c)

	work:    [THREAD_COUNT]Thread_Work
	threads: [THREAD_COUNT]^thread.Thread

	for i in 0 ..< THREAD_COUNT {
		work[i] = {cache = &c, key = 1}
		threads[i] = thread.create_and_start_with_data(&work[i], get_and_release_worker)
	}
	for i in 0 ..< THREAD_COUNT {
		thread.join(threads[i])
		thread.destroy(threads[i])
	}

	first := work[0].result
	for i in 1 ..< THREAD_COUNT {
		testing.expect(t, work[i].result == first)
	}
}

// After concurrent cold misses for the same key there should be exactly one
// entry carrying that key.  A double-claim leaves duplicates; those duplicates
// then cause block_cache_release to unlock the wrong entry's mutex.
@(test)
cache_no_duplicate_entries_for_same_key :: proc(t: ^testing.T) {
	c: rifle.BlockCache
	rifle.block_cache_init(&c, 16, BLOCK_SIZE)
	defer rifle.block_cache_destroy(&c)

	work:    [THREAD_COUNT]Thread_Work
	threads: [THREAD_COUNT]^thread.Thread

	for i in 0 ..< THREAD_COUNT {
		work[i] = {cache = &c, key = 1}
		threads[i] = thread.create_and_start_with_data(&work[i], get_and_release_worker)
	}
	for i in 0 ..< THREAD_COUNT {
		thread.join(threads[i])
		thread.destroy(threads[i])
	}

	count := 0
	for &e in c.entries {
		if e.key == 1 do count += 1
	}
	testing.expect_value(t, count, 1)
}

// ─── claim() window race ──────────────────────────────────────────────────────
//
// Inside claim(), the exclusive lock is released before the shared lock is
// acquired.  In that window another thread can claim the same entry for a
// different key.  The original thread then acquires a shared lock on an entry
// whose key no longer matches; its subsequent block_cache_release can't find
// the key and silently no-ops, leaking the shared lock.  The next eviction
// that tries to write-lock that entry will spin forever.
//
// This test exposes the window by maximising eviction pressure: 8 threads all
// targeting the same 4-slot set (mask=0), each cycling through 8 keys so the
// set is in constant churn.  If the window race fires and leaks a shared lock
// this test will HANG at thread.join rather than merely fail.

Storm_Work :: struct {
	cache:  ^rifle.BlockCache,
	offset: i64,
	iters:  int,
}

storm_worker :: proc(data: rawptr) {
	w := cast(^Storm_Work)data
	for i in i64(0) ..< cast(i64)w.iters {
		// Keys rotate across 8 values all mapping to the same set (mask=0),
		// so every iteration is a potential eviction.
		key := (w.offset + i) % (CAPACITY * 2) + 1
		block, _ := rifle.block_cache_get(w.cache, key)
		_ = block.data[0]
		rifle.block_cache_release(w.cache, key)
	}
}

@(test)
cache_claim_window_eviction_storm :: proc(t: ^testing.T) {
	// CAPACITY=4, mask=0: all keys land in the same 4-slot set.
	c: rifle.BlockCache
	rifle.block_cache_init(&c, CAPACITY, BLOCK_SIZE)
	defer rifle.block_cache_destroy(&c)

	STORM_THREADS :: 8
	STORM_ITERS   :: 500

	work:    [STORM_THREADS]Storm_Work
	threads: [STORM_THREADS]^thread.Thread

	for i in 0 ..< STORM_THREADS {
		work[i] = {cache = &c, offset = cast(i64)i, iters = STORM_ITERS}
		threads[i] = thread.create_and_start_with_data(&work[i], storm_worker)
	}
	for i in 0 ..< STORM_THREADS {
		thread.join(threads[i])
		thread.destroy(threads[i])
	}
}

// ─── Blocking fallback path ───────────────────────────────────────────────────
//
// When try_lock fails for every entry in a set the code falls back to a
// blocking sync.lock on the oldest entry.  This only triggers when more
// threads want a slot than there are slots (ASSOC=4 here, 8 threads).  The
// first 4 threads claim all 4 entries; the remaining 4 must block and wait.
// Once the holders release, the waiters should proceed — no deadlock.
// This test should pass; it guards the blocking path against regressions.

@(test)
cache_contention_exceeds_associativity :: proc(t: ^testing.T) {
	// CAPACITY=4, mask=0: 4 slots, 8 threads.
	c: rifle.BlockCache
	rifle.block_cache_init(&c, CAPACITY, BLOCK_SIZE)
	defer rifle.block_cache_destroy(&c)

	OVER_THREADS :: 8

	work:    [OVER_THREADS]Thread_Work
	threads: [OVER_THREADS]^thread.Thread

	for i in 0 ..< OVER_THREADS {
		work[i] = {cache = &c, key = cast(i64)(i + 1)}
		threads[i] = thread.create_and_start_with_data(&work[i], get_and_release_worker)
	}
	for i in 0 ..< OVER_THREADS {
		thread.join(threads[i])
		thread.destroy(threads[i])
	}

	for i in 0 ..< OVER_THREADS {
		testing.expect(t, work[i].result != nil)
	}
}
