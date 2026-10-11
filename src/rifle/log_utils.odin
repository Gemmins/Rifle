package rifle

import "core:sync"

check_log_index_ok :: proc {
	check_log_index_ok_single,
	check_log_index_ok_range,
}

check_log_index_ok_single :: proc(l: ^Log, index: i64) -> RifleError {
	return index >= sync.atomic_load(&l.commit_index.value) || index < sync.atomic_load(&l.tail_index.value) ? .IndexOutOfBoundsError : nil
}

check_log_index_ok_range :: proc(l: ^Log, start: i64, end: i64) -> RifleError {
	check_log_index_ok_single(l, start) or_return
	check_log_index_ok_single(l, end) or_return
	return end - start < 0 ? .IndexOutOfBoundsError : nil
}

get_block_and_offset :: proc(l: ^Log, index: i64) -> (block: i64, offset: i64) {
	block = index >> l.record_shift
	offset = (index & (l.records_per_block - 1)) * l.record_size
	return
}

get_file_index_and_offset :: proc(l: ^Log, index: i64) -> (file: i64, offset: i64) {
	block := index >> l.record_shift
	file = block >> l.block_shift
	offset = (block & (l.blocks_per_file - 1)) * (l.record_size * l.records_per_block)
	return
}
