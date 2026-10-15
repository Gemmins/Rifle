package test

import rifle "rifle:rifle"
import "core:testing"

// Helpers ---------------------------------------------------------------

// Builds a buffer holding `count` records of size L_RECORD_SIZE; record i's
// first byte is `start + i` so we can verify per-record identity later.
make_records :: proc(count: i64, start: u8) -> []u8 {
	buf := make([]u8, L_RECORD_SIZE * count)
	for i in 0 ..< count {
		off := i * L_RECORD_SIZE
		buf[off] = start + u8(i)
		// rest of the record stays zero — good enough to detect torn copies.
	}
	return buf
}

// --- Append many: basic ---

@(test)
log_append_many_increments_head_by_count :: proc(t: ^testing.T) {
	l, dir := make_test_log(t, "append_many_increments_head")
	defer destroy_test_log(l, dir)

	recs := make_records(3, 0)
	defer delete(recs)

	_, err := rifle.log_append_many(l, recs, 3)
	testing.expect_value(t, err, rifle.RifleError.None)
	testing.expect_value(t, rifle.log_head_index(l), i64(3))
}

@(test)
log_append_many_returns_first_index :: proc(t: ^testing.T) {
	l, dir := make_test_log(t, "append_many_returns_first_index")
	defer destroy_test_log(l, dir)

	// Single append to bump head off zero.
	single := make_records(1, 0xAA)
	defer delete(single)
	rifle.log_append(l, single)

	recs := make_records(4, 0)
	defer delete(recs)

	idx, err := rifle.log_append_many(l, recs, 4)
	testing.expect_value(t, err, rifle.RifleError.None)
	testing.expect_value(t, idx, i64(1))
}

// --- Append many: round-trip ---

@(test)
log_append_many_records_read_back_in_order :: proc(t: ^testing.T) {
	l, dir := make_test_log(t, "append_many_round_trip", SPILL_CACHE)
	defer destroy_test_log(l, dir)

	N := L_RECORDS_PER_BLOCK * 3 // block-aligned, exceeds the spill cache
	recs := make_records(N, 0)
	defer delete(recs)

	_, err := rifle.log_append_many(l, recs, N)
	testing.expect_value(t, err, rifle.RifleError.None)

	buf := make([]u8, L_RECORD_SIZE)
	defer delete(buf)
	for i in i64(0) ..< N {
		read_err := rifle.log_read_index(l, buf, i)
		testing.expect_value(t, read_err, rifle.RifleError.None)
		testing.expect_value(t, buf[0], u8(i))
	}
}

// --- Append many: boundary crossing ---

@(test)
log_append_many_across_block_boundary :: proc(t: ^testing.T) {
	l, dir := make_test_log(t, "append_many_block_boundary", SPILL_CACHE)
	defer destroy_test_log(l, dir)

	N := L_RECORDS_PER_BLOCK * 4 // block-aligned so the target block evicts to disk
	recs := make_records(N, 0)
	defer delete(recs)

	_, err := rifle.log_append_many(l, recs, N)
	testing.expect_value(t, err, rifle.RifleError.None)

	buf := make([]u8, L_RECORD_SIZE)
	defer delete(buf)
	read_err := rifle.log_read_index(l, buf, L_RECORDS_PER_BLOCK)
	testing.expect_value(t, read_err, rifle.RifleError.None)
	testing.expect_value(t, buf[0], u8(L_RECORDS_PER_BLOCK))
}

@(test)
log_append_many_across_file_boundary :: proc(t: ^testing.T) {
	l, dir := make_test_log(t, "append_many_file_boundary", SPILL_CACHE)
	defer destroy_test_log(l, dir)

	N := L_RECORDS_PER_FILE * 2 // block-aligned so the target block evicts to disk
	recs := make_records(N, 0)
	defer delete(recs)

	_, err := rifle.log_append_many(l, recs, N)
	testing.expect_value(t, err, rifle.RifleError.None)

	buf := make([]u8, L_RECORD_SIZE)
	defer delete(buf)
	read_err := rifle.log_read_index(l, buf, L_RECORDS_PER_FILE)
	testing.expect_value(t, read_err, rifle.RifleError.None)
	testing.expect_value(t, buf[0], u8(L_RECORDS_PER_FILE % 256))
}

// --- Read many: basic ---

@(test)
log_read_many_returns_all_records :: proc(t: ^testing.T) {
	l, dir := make_test_log(t, "read_many_basic", SPILL_CACHE)
	defer destroy_test_log(l, dir)

	N := L_RECORDS_PER_BLOCK * 3 // block-aligned, exceeds the spill cache
	for i in i64(0) ..< N {
		rec := make_record(u8(i))
		rifle.log_append(l, rec)
		delete(rec)
	}

	buf := make([]u8, L_RECORD_SIZE * N)
	defer delete(buf)
	err := rifle.log_read_many_index(l, buf, 0, N)
	testing.expect_value(t, err, rifle.RifleError.None)

	for i in i64(0) ..< N {
		off := i * L_RECORD_SIZE
		testing.expect_value(t, buf[off], u8(i))
	}
}

@(test)
log_read_many_partial_range :: proc(t: ^testing.T) {
	l, dir := make_test_log(t, "read_many_partial_range", SPILL_CACHE)
	defer destroy_test_log(l, dir)

	// Append several full blocks past the cache, then read [2, 5) — the early
	// records come back from disk.
	for i in u8(0) ..< u8(L_RECORDS_PER_BLOCK * 3) {
		rec := make_record(i)
		rifle.log_append(l, rec)
		delete(rec)
	}

	buf := make([]u8, L_RECORD_SIZE * 3)
	defer delete(buf)
	err := rifle.log_read_many_index(l, buf, 2, 5)
	testing.expect_value(t, err, rifle.RifleError.None)

	for i in i64(0) ..< 3 {
		off := i * L_RECORD_SIZE
		testing.expect_value(t, buf[off], u8(i + 2))
	}
}

// --- Read many: validation ---

@(test)
log_read_many_beyond_head_returns_error :: proc(t: ^testing.T) {
	l, dir := make_test_log(t, "read_many_beyond_head")
	defer destroy_test_log(l, dir)

	rec := make_record(0)
	defer delete(rec)
	rifle.log_append(l, rec)

	buf := make([]u8, L_RECORD_SIZE * 3)
	defer delete(buf)
	err := rifle.log_read_many_index(l, buf, 0, 3)
	testing.expect_value(t, err, rifle.RifleError.IndexOutOfBoundsError)
}

@(test)
log_read_many_empty_range_returns_error :: proc(t: ^testing.T) {
	l, dir := make_test_log(t, "read_many_empty_range")
	defer destroy_test_log(l, dir)

	rec := make_record(0)
	defer delete(rec)
	rifle.log_append(l, rec)

	buf := make([]u8, L_RECORD_SIZE)
	defer delete(buf)
	err := rifle.log_read_many_index(l, buf, 1, 1)
	testing.expect_value(t, err, rifle.RifleError.IndexOutOfBoundsError)
}

@(test)
log_read_many_before_tail_returns_error :: proc(t: ^testing.T) {
	l, dir := make_test_log(t, "read_many_before_tail")
	defer destroy_test_log(l, dir)

	for i in u8(0) ..< 4 {
		rec := make_record(i)
		rifle.log_append(l, rec)
		delete(rec)
	}
	rifle.log_advance_tail(l, 2)

	buf := make([]u8, L_RECORD_SIZE * 2)
	defer delete(buf)
	err := rifle.log_read_many_index(l, buf, 0, 2)
	testing.expect_value(t, err, rifle.RifleError.IndexOutOfBoundsError)
}

// --- Read many: boundary crossing ---

@(test)
log_read_many_across_block_boundary :: proc(t: ^testing.T) {
	l, dir := make_test_log(t, "read_many_block_boundary", SPILL_CACHE)
	defer destroy_test_log(l, dir)

	N := L_RECORDS_PER_BLOCK * 4 // block-aligned; the read range comes off disk
	for i in i64(0) ..< N {
		rec := make_record(u8(i))
		rifle.log_append(l, rec)
		delete(rec)
	}

	// Spans the boundary at L_RECORDS_PER_BLOCK.
	buf := make([]u8, L_RECORD_SIZE * 3)
	defer delete(buf)
	err := rifle.log_read_many_index(l, buf, L_RECORDS_PER_BLOCK - 1, L_RECORDS_PER_BLOCK + 2)
	testing.expect_value(t, err, rifle.RifleError.None)

	testing.expect_value(t, buf[0], u8(L_RECORDS_PER_BLOCK - 1))
	testing.expect_value(t, buf[L_RECORD_SIZE], u8(L_RECORDS_PER_BLOCK))
	testing.expect_value(t, buf[L_RECORD_SIZE * 2], u8(L_RECORDS_PER_BLOCK + 1))
}

@(test)
log_read_many_across_file_boundary :: proc(t: ^testing.T) {
	l, dir := make_test_log(t, "read_many_file_boundary", SPILL_CACHE)
	defer destroy_test_log(l, dir)

	N := L_RECORDS_PER_FILE * 2 // block-aligned; the read range comes off disk
	for i in i64(0) ..< N {
		rec := make_record(u8(i % 256))
		rifle.log_append(l, rec)
		delete(rec)
	}

	buf := make([]u8, L_RECORD_SIZE * 3)
	defer delete(buf)
	err := rifle.log_read_many_index(l, buf, L_RECORDS_PER_FILE - 1, L_RECORDS_PER_FILE + 2)
	testing.expect_value(t, err, rifle.RifleError.None)

	testing.expect_value(t, buf[0], u8((L_RECORDS_PER_FILE - 1) % 256))
	testing.expect_value(t, buf[L_RECORD_SIZE], u8(L_RECORDS_PER_FILE % 256))
	testing.expect_value(t, buf[L_RECORD_SIZE * 2], u8((L_RECORDS_PER_FILE + 1) % 256))
}

// --- Round-trip via both bulk APIs ---

@(test)
log_append_many_read_many_round_trip :: proc(t: ^testing.T) {
	l, dir := make_test_log(t, "append_many_read_many_round_trip", SPILL_CACHE)
	defer destroy_test_log(l, dir)

	N := L_RECORDS_PER_BLOCK * 3 // block-aligned, spans blocks past the spill cache
	recs := make_records(N, 0)
	defer delete(recs)

	_, err := rifle.log_append_many(l, recs, N)
	testing.expect_value(t, err, rifle.RifleError.None)

	buf := make([]u8, L_RECORD_SIZE * N)
	defer delete(buf)
	read_err := rifle.log_read_many_index(l, buf, 0, N)
	testing.expect_value(t, read_err, rifle.RifleError.None)

	for i in i64(0) ..< N {
		off := i * L_RECORD_SIZE
		testing.expect_value(t, buf[off], u8(i % 256))
	}
}

// A block completed across two separate append_many calls must still flush when
// it fills. Each call writes half a block, so a block only reaches full on its
// second call — the case where counting chunks instead of records misses that
// the block is now full. Writes many such blocks past the spill cache and reads
// the early ones back from disk; if a completed block never flushed, its data is
// gone once it's evicted.
@(test)
log_append_many_completes_block_across_calls :: proc(t: ^testing.T) {
	l, dir := make_test_log(t, "append_many_completes_block_across_calls", SPILL_CACHE)
	defer destroy_test_log(l, dir)

	half := L_RECORDS_PER_BLOCK / 2
	total := L_CACHE_BLOCKS * 2 * L_RECORDS_PER_BLOCK // 16 blocks, well past the cache

	// Append in half-block batches so each block completes on its second batch.
	for written := i64(0); written < total; written += half {
		recs := make_records(half, u8(written))
		_, err := rifle.log_append_many(l, recs, half)
		testing.expect_value(t, err, rifle.RifleError.None)
		delete(recs)
	}
	testing.expect_value(t, rifle.log_head_index(l), total)

	buf := make([]u8, L_RECORD_SIZE)
	defer delete(buf)
	for i in i64(0) ..< total {
		read_err := rifle.log_read_index(l, buf, i)
		testing.expect_value(t, read_err, rifle.RifleError.None)
		testing.expect_value(t, buf[0], u8(i))
	}
}
