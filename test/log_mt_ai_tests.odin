package test

import rifle "rifle:rifle"
import "core:fmt"
import "core:sync"
import "core:testing"
import "core:thread"

// Multi-threaded log tests. Each producer thread writes a distinct sentinel
// pattern so we can detect lost, duplicated, or torn writes after the run.

MT_THREADS          :: 4
MT_RECORDS_PER_THREAD :: 256
MT_TOTAL_RECORDS    :: MT_THREADS * MT_RECORDS_PER_THREAD

MT_Producer :: struct {
	l:         ^rifle.Log_old,
	thread_id: int,
	count:     int,
	err:       rifle.RifleError,
}

// Each record is filled with (thread_id << 16) | i in the first 8 bytes so we
// can recover both the producing thread and the per-thread sequence number.
mt_producer_proc :: proc(t: ^thread.Thread) {
	w := cast(^MT_Producer)t.data
	rec := make([]u8, L_RECORD_SIZE)
	defer delete(rec)
	for i in 0 ..< w.count {
		tag := i64(w.thread_id) << 32 | i64(i)
		(cast(^i64)raw_data(rec))^ = tag
		_, err := rifle.log_append(w.l, rec)
		if err != rifle.RifleError.None {
			w.err = err
			return
		}
	}
}

run_producers :: proc(l: ^rifle.Log_old, n_threads, records_per_thread: int) -> []MT_Producer {
	producers := make([]MT_Producer, n_threads)
	threads := make([]^thread.Thread, n_threads)
	defer delete(threads)

	for i in 0 ..< n_threads {
		producers[i] = MT_Producer{l = l, thread_id = i, count = records_per_thread}
		threads[i] = thread.create(mt_producer_proc)
		threads[i].data = &producers[i]
		thread.start(threads[i])
	}
	for t in threads {
		thread.join(t)
		thread.destroy(t)
	}
	return producers
}

// --- Smoke ---

@(test)
log_mt_all_appends_succeed :: proc(t: ^testing.T) {
	l, dir := make_test_log(t, "mt_all_appends_succeed")
	defer destroy_test_log(l, dir)

	producers := run_producers(l, MT_THREADS, MT_RECORDS_PER_THREAD)
	defer delete(producers)

	for &p in producers {
		testing.expect_value(t, p.err, rifle.RifleError.None)
	}
	testing.expect_value(t, rifle.log_head_index(l), i64(MT_TOTAL_RECORDS))
}

// --- Per-record correctness ---
//
// Read every slot and verify each carries a (thread, seq) pair that was
// actually written. Counts how many times each pair appeared.
@(test)
log_mt_every_record_exactly_once :: proc(t: ^testing.T) {
	l, dir := make_test_log(t, "mt_every_record_exactly_once")
	defer destroy_test_log(l, dir)

	producers := run_producers(l, MT_THREADS, MT_RECORDS_PER_THREAD)
	defer delete(producers)

	seen := make([][]int, MT_THREADS)
	defer {
		for s in seen do delete(s)
		delete(seen)
	}
	for i in 0 ..< MT_THREADS do seen[i] = make([]int, MT_RECORDS_PER_THREAD)

	buf := make([]u8, L_RECORD_SIZE)
	defer delete(buf)

	for i in i64(0) ..< MT_TOTAL_RECORDS {
		err := rifle.log_read_index(l, buf, i)
		testing.expect_value(t, err, rifle.RifleError.None)

		tag := (cast(^i64)raw_data(buf))^
		tid := int(tag >> 32)
		seq := int(tag & 0xFFFFFFFF)

		testing.expect(t, tid >= 0 && tid < MT_THREADS, fmt.tprintf("bad tid %d at index %d", tid, i))
		testing.expect(
			t,
			seq >= 0 && seq < MT_RECORDS_PER_THREAD,
			fmt.tprintf("bad seq %d at index %d", seq, i),
		)
		if tid >= 0 && tid < MT_THREADS && seq >= 0 && seq < MT_RECORDS_PER_THREAD {
			seen[tid][seq] += 1
		}
	}

	for tid in 0 ..< MT_THREADS {
		for seq in 0 ..< MT_RECORDS_PER_THREAD {
			testing.expect_value(t, seen[tid][seq], 1)
		}
	}
}

// --- Per-thread sequence preservation ---
//
// Records from the same producer are claimed via fetch_add, so their slot
// indices are strictly increasing. Reading the log in order should yield
// each producer's sequence numbers in order too.
@(test)
log_mt_per_thread_order_preserved :: proc(t: ^testing.T) {
	l, dir := make_test_log(t, "mt_per_thread_order_preserved")
	defer destroy_test_log(l, dir)

	producers := run_producers(l, MT_THREADS, MT_RECORDS_PER_THREAD)
	defer delete(producers)

	last_seq := make([]int, MT_THREADS)
	defer delete(last_seq)
	for i in 0 ..< MT_THREADS do last_seq[i] = -1

	buf := make([]u8, L_RECORD_SIZE)
	defer delete(buf)

	for i in i64(0) ..< MT_TOTAL_RECORDS {
		rifle.log_read_index(l, buf, i)
		tag := (cast(^i64)raw_data(buf))^
		tid := int(tag >> 32)
		seq := int(tag & 0xFFFFFFFF)
		if tid < 0 || tid >= MT_THREADS do continue
		testing.expect(
			t,
			seq > last_seq[tid],
			fmt.tprintf(
				"thread %d went backwards at index %d: %d after %d",
				tid,
				i,
				seq,
				last_seq[tid],
			),
		)
		last_seq[tid] = seq
	}
}

// --- Eviction stress ---
//
// Forces records-written to exceed the cache so blocks are evicted (and must
// be re-fetched from disk on read). The cache holds L_CACHE_BLOCKS blocks of
// L_RECORDS_PER_BLOCK records each. We write enough to need ~8x that.
@(test)
log_mt_exceeds_cache_capacity :: proc(t: ^testing.T) {
	l, dir := make_test_log(t, "mt_exceeds_cache_capacity")
	defer destroy_test_log(l, dir)

	cache_records := int(L_CACHE_BLOCKS * L_RECORDS_PER_BLOCK)
	per_thread := cache_records * 8 / MT_THREADS
	total := per_thread * MT_THREADS

	producers := run_producers(l, MT_THREADS, per_thread)
	defer delete(producers)
	for &p in producers {
		testing.expect_value(t, p.err, rifle.RifleError.None)
	}

	testing.expect_value(t, rifle.log_head_index(l), i64(total))

	buf := make([]u8, L_RECORD_SIZE)
	defer delete(buf)

	seen := make([][]int, MT_THREADS)
	defer {
		for s in seen do delete(s)
		delete(seen)
	}
	for i in 0 ..< MT_THREADS do seen[i] = make([]int, per_thread)

	for i in i64(0) ..< i64(total) {
		err := rifle.log_read_index(l, buf, i)
		testing.expect_value(t, err, rifle.RifleError.None)

		tag := (cast(^i64)raw_data(buf))^
		tid := int(tag >> 32)
		seq := int(tag & 0xFFFFFFFF)
		if tid < 0 || tid >= MT_THREADS do continue
		if seq < 0 || seq >= per_thread do continue
		seen[tid][seq] += 1
	}

	for tid in 0 ..< MT_THREADS {
		for seq in 0 ..< per_thread {
			testing.expect_value(t, seen[tid][seq], 1)
		}
	}
}

// --- Concurrent readers and writers ---
//
// A shuffled list of every slot index is partitioned across reader threads.
// Each reader walks its slice in order, waiting for the commit cursor to
// catch up to each target before reading. This guarantees every slot is read
// exactly once across all readers, in a random order that defeats sequential
// cache locality and forces evicted blocks to be re-fetched from disk.

MT_Reader :: struct {
	l:         ^rifle.Log_old,
	targets:   []i64,
	bad_reads: int,
	seen:      [][]int, // [thread_id][seq] count, owned by parent
}

mt_reader_proc :: proc(t: ^thread.Thread) {
	r := cast(^MT_Reader)t.data
	buf := make([]u8, L_RECORD_SIZE)
	defer delete(buf)
	for idx in r.targets {
		for rifle.log_head_index(r.l) <= idx {} // spin until committed
		err := rifle.log_read_index(r.l, buf, idx)
		if err != rifle.RifleError.None {
			r.bad_reads += 1
			continue
		}
		tag := (cast(^i64)raw_data(buf))^
		tid := int(tag >> 32)
		seq := int(tag & 0xFFFFFFFF)
		if tid < 0 || tid >= MT_THREADS || seq < 0 || seq >= MT_RECORDS_PER_THREAD {
			r.bad_reads += 1
			continue
		}
		sync.atomic_add(&r.seen[tid][seq], 1)
	}
}

@(test)
log_mt_concurrent_readers_writers :: proc(t: ^testing.T) {
	l, dir := make_test_log(t, "mt_concurrent_readers_writers")
	defer destroy_test_log(l, dir)

	N_READERS :: 2

	// Shuffled list of every slot index — partitioned evenly across readers.
	indices := make([]i64, MT_TOTAL_RECORDS)
	defer delete(indices)
	for i in 0 ..< MT_TOTAL_RECORDS do indices[i] = i64(i)
	rng := u64(0xC0FFEE)
	for i := MT_TOTAL_RECORDS - 1; i > 0; i -= 1 {
		rng ~= rng << 13
		rng ~= rng >> 7
		rng ~= rng << 17
		j := int(rng % u64(i + 1))
		indices[i], indices[j] = indices[j], indices[i]
	}

	// Shared seen[tid][seq] counts so we can verify every record was read once.
	seen := make([][]int, MT_THREADS)
	defer {
		for s in seen do delete(s)
		delete(seen)
	}
	for i in 0 ..< MT_THREADS do seen[i] = make([]int, MT_RECORDS_PER_THREAD)

	readers := make([]MT_Reader, N_READERS)
	reader_threads := make([]^thread.Thread, N_READERS)
	defer delete(readers)
	defer delete(reader_threads)

	chunk := MT_TOTAL_RECORDS / N_READERS
	for i in 0 ..< N_READERS {
		lo := i * chunk
		hi := i < N_READERS - 1 ? (i + 1) * chunk : MT_TOTAL_RECORDS
		readers[i] = MT_Reader{l = l, targets = indices[lo:hi], seen = seen}
		reader_threads[i] = thread.create(mt_reader_proc)
		reader_threads[i].data = &readers[i]
		thread.start(reader_threads[i])
	}

	producers := run_producers(l, MT_THREADS, MT_RECORDS_PER_THREAD)
	defer delete(producers)

	for rt in reader_threads {
		thread.join(rt)
		thread.destroy(rt)
	}

	for &p in producers {
		testing.expect_value(t, p.err, rifle.RifleError.None)
	}
	for &r in readers {
		testing.expect_value(t, r.bad_reads, 0)
	}
	for tid in 0 ..< MT_THREADS {
		for seq in 0 ..< MT_RECORDS_PER_THREAD {
			testing.expect_value(t, seen[tid][seq], 1)
		}
	}
}
