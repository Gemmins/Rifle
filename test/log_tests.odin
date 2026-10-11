package test

import rifle "rifle:rifle"
import "core:fmt"
import "core:os"
import "core:testing"

// Small power-of-two params to keep tests fast and boundary conditions reachable.
L_RECORD_SIZE       :: i64(64)
L_RECORDS_PER_BLOCK :: i64(4)
L_BLOCKS_PER_FILE   :: i64(4)
L_CACHE_BLOCKS      :: i64(8)
L_MAX_OPEN_FILES    :: i64(4)

// Records per file, useful for boundary tests.
L_RECORDS_PER_FILE :: L_RECORDS_PER_BLOCK * L_BLOCKS_PER_FILE

// Deliberately tiny cache: forces full blocks to be evicted and re-read from
// disk. Only safe with block-aligned record counts — a partial tail block stays
// pinned in cache and, with the direct-mapped cache, a read that collides with
// its slot would spin forever rather than miss.
SPILL_CACHE :: i64(2)

make_test_log :: proc(
	t: ^testing.T,
	name: string,
	cache_blocks: i64 = L_CACHE_BLOCKS,
) -> (^rifle.Log, string) {
	td, _ := os.temp_dir(context.allocator)
	dir := fmt.aprintf("%s/rifle_%s", td, name)
	delete(td)
	os.make_directory(dir)
	l, err := rifle.log_create(
		dir,
		L_RECORD_SIZE,
		L_RECORDS_PER_BLOCK,
		L_BLOCKS_PER_FILE,
		cache_blocks,
		L_MAX_OPEN_FILES,
	)
	testing.expect_value(t, err, rifle.RifleError.None)
	return l, dir
}

destroy_test_log :: proc(l: ^rifle.Log, dir: string) {
	rifle.log_destroy(l)
	// TODO: recursively remove dir and its contents
	delete(dir)
}

make_record :: proc(fill: u8) -> []u8 {
	rec := make([]u8, L_RECORD_SIZE)
	for &b in rec {b = fill}
	return rec
}

// --- Lifecycle ---

@(test)
log_create_destroy :: proc(t: ^testing.T) {
	l, dir := make_test_log(t, "create_destroy")
	testing.expect(t, l != nil)
	destroy_test_log(l, dir)
}

@(test)
log_create_non_power_of_two_returns_error :: proc(t: ^testing.T) {
	td, _ := os.temp_dir(context.allocator)
	dir := fmt.aprintf("%s/rifle_invalid_args", td)
	defer delete(td)
	defer delete(dir)

	_, err := rifle.log_create(dir, L_RECORD_SIZE, 3, L_BLOCKS_PER_FILE, L_CACHE_BLOCKS, L_MAX_OPEN_FILES)
	testing.expect_value(t, err, rifle.RifleError.InvalidArgError)

	_, err2 := rifle.log_create(dir, L_RECORD_SIZE, L_RECORDS_PER_BLOCK, 3, L_CACHE_BLOCKS, L_MAX_OPEN_FILES)
	testing.expect_value(t, err2, rifle.RifleError.InvalidArgError)
}

// --- Index accessors ---

@(test)
log_initial_indices :: proc(t: ^testing.T) {
	l, dir := make_test_log(t, "initial_indices")
	defer destroy_test_log(l, dir)

	testing.expect_value(t, rifle.log_head_index(l), i64(0))
	testing.expect_value(t, rifle.log_tail_index(l), i64(0))
}

// --- Append ---

@(test)
log_append_increments_head :: proc(t: ^testing.T) {
	l, dir := make_test_log(t, "append_increments_head")
	defer destroy_test_log(l, dir)

	rec := make_record(0xAB)
	defer delete(rec)

	_, err := rifle.log_append(l, rec)
	testing.expect_value(t, err, rifle.RifleError.None)
	testing.expect_value(t, rifle.log_head_index(l), i64(1))
}

@(test)
log_append_returns_sequential_indices :: proc(t: ^testing.T) {
	l, dir := make_test_log(t, "append_returns_indices")
	defer destroy_test_log(l, dir)

	rec := make_record(0)
	defer delete(rec)

	for i in i64(0) ..< 4 {
		idx, err := rifle.log_append(l, rec)
		testing.expect_value(t, err, rifle.RifleError.None)
		testing.expect_value(t, idx, i)
	}
}

// --- Read ---

@(test)
log_append_read_back :: proc(t: ^testing.T) {
	l, dir := make_test_log(t, "append_read_back")
	defer destroy_test_log(l, dir)

	rec := make_record(0)
	defer delete(rec)
	rec[0] = 0xDE
	rec[1] = 0xAD

	idx, _ := rifle.log_append(l, rec)

	buf := make([]u8, L_RECORD_SIZE)
	defer delete(buf)
	err := rifle.log_read_index(l, buf, idx)
	testing.expect_value(t, err, rifle.RifleError.None)
	testing.expect_value(t, buf[0], u8(0xDE))
	testing.expect_value(t, buf[1], u8(0xAD))
}

@(test)
log_read_head_returns_last_appended :: proc(t: ^testing.T) {
	l, dir := make_test_log(t, "read_head")
	defer destroy_test_log(l, dir)

	for i in u8(0) ..< 3 {
		rec := make_record(i)
		rifle.log_append(l, rec)
		delete(rec)
	}

	buf := make([]u8, L_RECORD_SIZE)
	defer delete(buf)
	err := rifle.log_read_head(l, buf)
	testing.expect_value(t, err, rifle.RifleError.None)
	testing.expect_value(t, buf[0], u8(2))
}

@(test)
log_read_tail_returns_at_tail_index :: proc(t: ^testing.T) {
	l, dir := make_test_log(t, "read_tail")
	defer destroy_test_log(l, dir)

	for i in u8(0) ..< 3 {
		rec := make_record(i)
		rifle.log_append(l, rec)
		delete(rec)
	}

	buf := make([]u8, L_RECORD_SIZE)
	defer delete(buf)
	err := rifle.log_read_tail(l, buf)
	testing.expect_value(t, err, rifle.RifleError.None)
	testing.expect_value(t, buf[0], u8(0))
}

@(test)
log_read_empty_log_returns_error :: proc(t: ^testing.T) {
	l, dir := make_test_log(t, "read_empty")
	defer destroy_test_log(l, dir)

	buf := make([]u8, L_RECORD_SIZE)
	defer delete(buf)

	err := rifle.log_read_index(l, buf, 0)
	testing.expect_value(t, err, rifle.RifleError.IndexOutOfBoundsError)
}

@(test)
log_read_beyond_head_returns_error :: proc(t: ^testing.T) {
	l, dir := make_test_log(t, "read_beyond_head")
	defer destroy_test_log(l, dir)

	rec := make_record(0)
	defer delete(rec)
	rifle.log_append(l, rec)

	buf := make([]u8, L_RECORD_SIZE)
	defer delete(buf)
	err := rifle.log_read_index(l, buf, 1)
	testing.expect_value(t, err, rifle.RifleError.IndexOutOfBoundsError)
}

// --- Tail advancement ---

@(test)
log_advance_tail_updates_index :: proc(t: ^testing.T) {
	l, dir := make_test_log(t, "advance_tail")
	defer destroy_test_log(l, dir)

	for i in 0 ..< 4 {
		rec := make_record(u8(i))
		rifle.log_append(l, rec)
		delete(rec)
	}

	rifle.log_advance_tail(l, 2)
	testing.expect_value(t, rifle.log_tail_index(l), i64(2))
}

@(test)
log_read_before_tail_returns_error :: proc(t: ^testing.T) {
	l, dir := make_test_log(t, "read_before_tail")
	defer destroy_test_log(l, dir)

	for i in 0 ..< 4 {
		rec := make_record(u8(i))
		rifle.log_append(l, rec)
		delete(rec)
	}
	rifle.log_advance_tail(l, 2)

	buf := make([]u8, L_RECORD_SIZE)
	defer delete(buf)
	err := rifle.log_read_index(l, buf, 0)
	testing.expect_value(t, err, rifle.RifleError.IndexOutOfBoundsError)
}

// --- Boundary crossing ---

@(test)
log_append_read_across_block_boundary :: proc(t: ^testing.T) {
	l, dir := make_test_log(t, "block_boundary", SPILL_CACHE)
	defer destroy_test_log(l, dir)

	// Write several full blocks past the cache so the target block is evicted
	// and its first record must be read back from disk.
	for i in i64(0) ..< L_RECORDS_PER_BLOCK * 4 {
		rec := make_record(u8(i))
		_, err := rifle.log_append(l, rec)
		testing.expect_value(t, err, rifle.RifleError.None)
		delete(rec)
	}

	buf := make([]u8, L_RECORD_SIZE)
	defer delete(buf)

	// First record of block 1 — should survive the block transition cleanly.
	err := rifle.log_read_index(l, buf, L_RECORDS_PER_BLOCK)
	testing.expect_value(t, err, rifle.RifleError.None)
	testing.expect_value(t, buf[0], u8(L_RECORDS_PER_BLOCK))
}

@(test)
log_append_read_across_file_boundary :: proc(t: ^testing.T) {
	l, dir := make_test_log(t, "file_boundary", SPILL_CACHE)
	defer destroy_test_log(l, dir)

	// Write two full files' worth so the first block of file 1 is evicted and
	// must be re-read from disk (opening the second storage file).
	for i in i64(0) ..< L_RECORDS_PER_FILE * 2 {
		rec := make_record(u8(i % 256))
		_, err := rifle.log_append(l, rec)
		testing.expect_value(t, err, rifle.RifleError.None)
		delete(rec)
	}

	buf := make([]u8, L_RECORD_SIZE)
	defer delete(buf)

	// First record of file 1 — should be readable after the file handle opens.
	err := rifle.log_read_index(l, buf, L_RECORDS_PER_FILE)
	testing.expect_value(t, err, rifle.RifleError.None)
	testing.expect_value(t, buf[0], u8(L_RECORDS_PER_FILE % 256))
}
