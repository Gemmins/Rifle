package unit

import "core:testing"
import "core:sys/posix"
import rifle "rifle:rifle"

LOG_TEST_FIELDS: [1]rifle.SchemaField = {{name = "value", type = .I64}}

Log_Cache_Spy :: struct {
	read_calls:  int,
	write_calls: int,
	poll_calls:  int,
	sync_calls:  int,
	index:       i64,
	count:       i64,
	data:        []u8,
	progress:    bool,
	err:         rifle.RifleError,
}

log_test_config :: proc() -> rifle.LogConfig {
	config := rifle.DefaultLogConfig
	config.log_path = "/tmp"
	config.ring_size_bytes = 1 << 16
	config.page_cache_size_bytes = 4 * 4096
	config.file_size_bytes = 2 * 4096
	config.page_size_bytes = 4096
	config.max_open_files = 2
	config.read_chunk_size = 0
	config.commit_ring_size = 8
	config.schema = {record_size = 8, fields = LOG_TEST_FIELDS[:]}
	return config
}

log_spy_cache :: proc(spy: ^Log_Cache_Spy) -> rifle.Cache {
	return {
		data = spy,
		read = proc(ctx: rawptr, data: []u8, index, count: i64) -> rifle.RifleError {
			spy := cast(^Log_Cache_Spy)ctx
			spy.read_calls += 1
			spy.index = index
			spy.count = count
			spy.data = data
			return spy.err
		},
		write = proc(ctx: rawptr, data: []u8, index, count: i64) -> rifle.RifleError {
			spy := cast(^Log_Cache_Spy)ctx
			spy.write_calls += 1
			spy.index = index
			spy.count = count
			spy.data = data
			return spy.err
		},
		poll = proc(ctx: rawptr) -> (bool, rifle.RifleError) {
			spy := cast(^Log_Cache_Spy)ctx
			spy.poll_calls += 1
			return spy.progress, spy.err
		},
		sync = proc(ctx: rawptr) {
			spy := cast(^Log_Cache_Spy)ctx
			spy.sync_calls += 1
		},
	}
}

@(test)
given_valid_log_config_when_validated_then_no_error_is_returned :: proc(t: ^testing.T) {
	// Arrange
	config := log_test_config()

	// Act
	err := rifle.log_config_validate(config)

	// Assert
	testing.expect_value(t, err, rifle.RifleError.None)
}

@(test)
given_invalid_log_configs_when_validated_then_each_is_rejected :: proc(t: ^testing.T) {
	// Arrange
	valid := log_test_config()
	invalid_fields := []rifle.SchemaField{{name = "invalid name", type = .I64}}
	cases: [21]rifle.LogConfig
	for &config in cases {
		config = valid
	}
	cases[0].log_path = nil
	cases[1].log_path = ""
	cases[2].page_size_bytes = 2048
	cases[3].page_size_bytes = 6144
	cases[4].ring_size_bytes = 2048
	cases[5].ring_size_bytes = 12288
	cases[6].ring_size_bytes = 1 << 37
	cases[7].page_cache_size_bytes = 0
	cases[8].page_cache_size_bytes = 5 * 4096
	cases[9].page_cache_size_bytes = 2 * 4096
	cases[10].read_chunk_size = -1
	cases[11].read_chunk_size = 2
	cases[12].file_size_bytes = 0
	cases[13].file_size_bytes = 4097
	cases[14].max_open_files = 0
	cases[15].max_open_files = 4097
	cases[16].commit_ring_size = 0
	cases[17].commit_ring_size = 3
	cases[18].schema.fields = nil
	cases[19].schema.record_size = 1 << 17
	cases[20].schema.fields = invalid_fields

	// Act
	errors: [len(cases)]rifle.RifleError
	for config, i in cases {
		errors[i] = rifle.log_config_validate(config)
	}

	// Assert
	for err in errors {
		testing.expect_value(t, err, rifle.RifleError.InvalidArgError)
	}
}

@(test)
given_visible_range_when_read_then_request_is_forwarded_to_cache :: proc(t: ^testing.T) {
	// Arrange
	spy: Log_Cache_Spy
	log: rifle.Log
	log.trailing_index.value = 5
	log.visible_index.value = 10
	log.cache = log_spy_cache(&spy)
	buffer: [16]u8

	// Act
	err := rifle.log_read(&log, buffer[:], 6, 2)

	// Assert
	testing.expect_value(t, err, rifle.RifleError.None)
	testing.expect_value(t, spy.read_calls, 1)
	testing.expect_value(t, spy.index, i64(6))
	testing.expect_value(t, spy.count, i64(2))
	testing.expect(t, raw_data(spy.data) == raw_data(buffer[:]))
}

@(test)
given_out_of_bounds_range_when_read_then_cache_is_not_called :: proc(t: ^testing.T) {
	// Arrange
	spy: Log_Cache_Spy
	log: rifle.Log
	log.trailing_index.value = 5
	log.visible_index.value = 10
	log.cache = log_spy_cache(&spy)
	cases := [5]struct {index, count: i64}{{4, 1}, {10, 1}, {-1, 1}, {5, -1}, {max(i64) - 1, 4}}

	// Act
	errors: [len(cases)]rifle.RifleError
	for test_case, i in cases {
		errors[i] = rifle.log_read(&log, nil, test_case.index, test_case.count)
	}

	// Assert
	for err in errors {
		testing.expect_value(t, err, rifle.RifleError.IndexOutOfBoundsError)
	}
	testing.expect_value(t, spy.read_calls, 0)
}

@(test)
given_cache_read_error_when_read_then_error_is_forwarded :: proc(t: ^testing.T) {
	// Arrange
	spy := Log_Cache_Spy{err = .FileOperationError}
	log: rifle.Log
	log.visible_index.value = 1
	log.cache = log_spy_cache(&spy)
	buffer: [8]u8

	// Act
	err := rifle.log_read(&log, buffer[:], 0, 1)

	// Assert
	testing.expect_value(t, err, rifle.RifleError.FileOperationError)
	testing.expect_value(t, spy.read_calls, 1)
}

@(test)
given_records_when_written_then_index_is_reserved_and_request_is_forwarded :: proc(t: ^testing.T) {
	// Arrange
	spy: Log_Cache_Spy
	log: rifle.Log
	log.commited_index.value = 7
	log.cache = log_spy_cache(&spy)
	data: [16]u8

	// Act
	index, err := rifle.log_write(&log, data[:], 2)

	// Assert
	testing.expect_value(t, err, rifle.RifleError.None)
	testing.expect_value(t, index, i64(7))
	testing.expect_value(t, log.commited_index.value, i64(9))
	testing.expect_value(t, spy.write_calls, 1)
	testing.expect_value(t, spy.index, i64(7))
	testing.expect_value(t, spy.count, i64(2))
	testing.expect(t, raw_data(spy.data) == raw_data(data[:]))
}

@(test)
given_negative_count_when_written_then_request_is_rejected_without_reservation :: proc(t: ^testing.T) {
	// Arrange
	spy: Log_Cache_Spy
	log: rifle.Log
	log.commited_index.value = 7
	log.cache = log_spy_cache(&spy)

	// Act
	index, err := rifle.log_write(&log, nil, -1)

	// Assert
	testing.expect_value(t, index, i64(0))
	testing.expect_value(t, err, rifle.RifleError.InvalidArgError)
	testing.expect_value(t, log.commited_index.value, i64(7))
	testing.expect_value(t, spy.write_calls, 0)
}

@(test)
given_visible_index_when_sync_is_requested_then_target_is_returned_and_cache_is_signalled :: proc(t: ^testing.T) {
	// Arrange
	spy: Log_Cache_Spy
	log: rifle.Log
	log.visible_index.value = 17
	log.cache = log_spy_cache(&spy)

	// Act
	target := rifle.log_sync(&log)

	// Assert
	testing.expect_value(t, target, i64(17))
	testing.expect_value(t, spy.sync_calls, 1)
}

@(test)
given_cache_poll_result_when_polled_then_progress_and_error_are_forwarded :: proc(t: ^testing.T) {
	// Arrange
	spy := Log_Cache_Spy{progress = true, err = .FileOperationError}
	log := rifle.Log{cache = log_spy_cache(&spy)}

	// Act
	progress, err := rifle.log_poll(&log)

	// Assert
	testing.expect(t, progress)
	testing.expect_value(t, err, rifle.RifleError.FileOperationError)
	testing.expect_value(t, spy.poll_calls, 1)
}

@(test)
given_visible_range_when_records_are_dropped_then_trailing_index_only_moves_forward :: proc(t: ^testing.T) {
	// Arrange
	log: rifle.Log
	log.visible_index.value = 10
	log.trailing_index.value = 2

	// Act
	first_err := rifle.log_drop(&log, 6)
	backward_err := rifle.log_drop(&log, 4)
	beyond_err := rifle.log_drop(&log, 11)

	// Assert
	testing.expect_value(t, first_err, rifle.RifleError.None)
	testing.expect_value(t, backward_err, rifle.RifleError.IndexOutOfBoundsError)
	testing.expect_value(t, beyond_err, rifle.RifleError.IndexOutOfBoundsError)
	testing.expect_value(t, log.trailing_index.value, i64(6))
}

@(test)
given_unimplemented_zero_copy_operations_when_called_then_unimplemented_error_is_returned :: proc(t: ^testing.T) {
	// Arrange
	log: rifle.Log

	// Act
	_, acquire_err := rifle.log_read_acquire(&log, 0, 1)
	release_err := rifle.log_read_release(&log, 0)
	prefetch_err := rifle.log_prefetch(&log, 0, 1)
	_, _, reserve_err := rifle.log_write_reserve(&log, 1)
	commit_err := rifle.log_write_commit(&log, 0)

	// Assert
	testing.expect_value(t, acquire_err, rifle.RifleError.UnimplementedError)
	testing.expect_value(t, release_err, rifle.RifleError.UnimplementedError)
	testing.expect_value(t, prefetch_err, rifle.RifleError.UnimplementedError)
	testing.expect_value(t, reserve_err, rifle.RifleError.UnimplementedError)
	testing.expect_value(t, commit_err, rifle.RifleError.UnimplementedError)
}

@(test)
given_log_config_when_arena_size_is_calculated_then_size_is_aligned_and_grows_with_capacity :: proc(t: ^testing.T) {
	// Arrange
	config := log_test_config()
	larger := config
	larger.ring_size_bytes *= 2
	larger.page_cache_size_bytes *= 2
	larger.max_open_files *= 2
	alignment := max(config.page_size_bytes, i64(posix.sysconf(._PAGE_SIZE)))

	// Act
	size := rifle.log_arena_size(config)
	larger_size := rifle.log_arena_size(larger)

	// Assert
	testing.expect(t, size > i64(size_of(rifle.Log)))
	testing.expect_value(t, size % alignment, i64(0))
	testing.expect_value(t, larger_size % alignment, i64(0))
	testing.expect(t, larger_size > size)
}
