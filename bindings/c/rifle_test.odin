#+test
package rifle_c

import "core:testing"
import rifle "rifle:rifle"

C_Binding_Cache_Spy :: struct {
	bytes:       [16]u8,
	read_calls:  int,
	write_calls: int,
	poll_calls:  int,
	sync_calls:  int,
	progress:    bool,
	err:         rifle.RifleError,
	visible:     ^i64,
}

c_binding_test_log :: proc(log: ^rifle.Log, spy: ^C_Binding_Cache_Spy) {
	log.config.schema.record_size = 8
	log.visible_index.value = 2
	spy.visible = &log.visible_index.value
	log.cache = {
		data = spy,
		read = proc(ctx: rawptr, output: []u8, index, count: i64) -> rifle.RifleError {
			spy := cast(^C_Binding_Cache_Spy)ctx
			spy.read_calls += 1
			copy(output, spy.bytes[index * 8:][:count * 8])
			return spy.err
		},
		write = proc(ctx: rawptr, input: []u8, index, count: i64) -> rifle.RifleError {
			spy := cast(^C_Binding_Cache_Spy)ctx
			spy.write_calls += 1
			copy(spy.bytes[index * 8:][:count * 8], input)
			spy.visible^ = index + count
			return spy.err
		},
		poll = proc(ctx: rawptr) -> (bool, rifle.RifleError) {
			spy := cast(^C_Binding_Cache_Spy)ctx
			spy.poll_calls += 1
			return spy.progress, spy.err
		},
		sync = proc(ctx: rawptr) {
			spy := cast(^C_Binding_Cache_Spy)ctx
			spy.sync_calls += 1
		},
	}
}

@(test)
given_output_config_when_defaults_are_requested_then_public_defaults_are_copied :: proc(t: ^testing.T) {
	// Arrange
	config: rifle.LogConfig

	// Act
	err := rifle_log_default_config(&config)

	// Assert
	testing.expect_value(t, err, rifle.RifleError.None)
	testing.expect_value(t, config.ring_size_bytes, rifle.DefaultLogConfig.ring_size_bytes)
	testing.expect_value(t, config.page_cache_size_bytes, rifle.DefaultLogConfig.page_cache_size_bytes)
	testing.expect_value(t, config.file_size_bytes, rifle.DefaultLogConfig.file_size_bytes)
	testing.expect_value(t, config.page_size_bytes, rifle.DefaultLogConfig.page_size_bytes)
	testing.expect_value(t, config.max_open_files, rifle.DefaultLogConfig.max_open_files)
	testing.expect_value(t, config.commit_ring_size, rifle.DefaultLogConfig.commit_ring_size)
}

@(test)
given_null_output_config_when_defaults_are_requested_then_invalid_argument_is_returned :: proc(t: ^testing.T) {
	// Arrange
	output: ^rifle.LogConfig = nil

	// Act
	err := rifle_log_default_config(output)

	// Assert
	testing.expect_value(t, err, rifle.RifleError.InvalidArgError)
}

@(test)
given_valid_buffers_when_records_are_written_and_read_then_calls_are_forwarded :: proc(t: ^testing.T) {
	// Arrange
	spy: C_Binding_Cache_Spy
	log: rifle.Log
	c_binding_test_log(&log, &spy)
	log.commited_index.value = 0
	input := [16]u8{1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16}
	output: [16]u8
	index: i64

	// Act
	write_err := rifle_log_write(&log, raw_data(input[:]), 16, 2, &index)
	read_err := rifle_log_read(&log, raw_data(output[:]), 16, 0, 2)

	// Assert
	testing.expect_value(t, write_err, rifle.RifleError.None)
	testing.expect_value(t, read_err, rifle.RifleError.None)
	testing.expect_value(t, index, i64(0))
	testing.expect_value(t, output, input)
	testing.expect_value(t, spy.write_calls, 1)
	testing.expect_value(t, spy.read_calls, 1)
}

@(test)
given_log_when_polled_synced_and_dropped_then_results_are_forwarded :: proc(t: ^testing.T) {
	// Arrange
	spy := C_Binding_Cache_Spy {
		progress = true,
	}
	log: rifle.Log
	c_binding_test_log(&log, &spy)
	progress: bool
	sync_index: i64

	// Act
	poll_err := rifle_log_poll(&log, &progress)
	sync_err := rifle_log_sync(&log, &sync_index)
	drop_err := rifle_log_drop(&log, 1)

	// Assert
	testing.expect_value(t, poll_err, rifle.RifleError.None)
	testing.expect_value(t, sync_err, rifle.RifleError.None)
	testing.expect_value(t, drop_err, rifle.RifleError.None)
	testing.expect(t, progress)
	testing.expect_value(t, sync_index, i64(2))
	testing.expect_value(t, log.trailing_index.value, i64(1))
	testing.expect_value(t, spy.poll_calls, 1)
	testing.expect_value(t, spy.sync_calls, 1)
}

@(test)
given_unimplemented_log_operations_when_called_through_binding_then_errors_and_empty_outputs_are_forwarded :: proc(t: ^testing.T) {
	// Arrange
	log: rifle.Log
	buffer: [1]u8
	read_buffer: [^]u8 = raw_data(buffer[:])
	write_buffer: [^]u8 = raw_data(buffer[:])
	write_index: i64 = 41

	// Act
	acquire_err := rifle_log_read_acquire(&log, 0, 1, &read_buffer)
	release_err := rifle_log_read_release(&log, 0)
	prefetch_err := rifle_log_prefetch(&log, 0, 1)
	reserve_err := rifle_log_write_reserve(&log, 1, &write_index, &write_buffer)
	commit_err := rifle_log_write_commit(&log, 0)

	// Assert
	testing.expect_value(t, acquire_err, rifle.RifleError.UnimplementedError)
	testing.expect_value(t, release_err, rifle.RifleError.UnimplementedError)
	testing.expect_value(t, prefetch_err, rifle.RifleError.UnimplementedError)
	testing.expect_value(t, reserve_err, rifle.RifleError.UnimplementedError)
	testing.expect_value(t, commit_err, rifle.RifleError.UnimplementedError)
	testing.expect(t, read_buffer == nil)
	testing.expect_value(t, write_index, i64(-1))
	testing.expect(t, write_buffer == nil)
}

@(test)
given_cache_write_error_when_written_through_binding_then_error_is_forwarded_and_output_index_is_cleared :: proc(t: ^testing.T) {
	// Arrange
	spy := C_Binding_Cache_Spy{err = .FileOperationError}
	log: rifle.Log
	c_binding_test_log(&log, &spy)
	data: [8]u8
	index: i64 = 41

	// Act
	err := rifle_log_write(&log, raw_data(data[:]), len(data), 1, &index)

	// Assert
	testing.expect_value(t, err, rifle.RifleError.FileOperationError)
	testing.expect_value(t, index, i64(-1))
	testing.expect_value(t, spy.write_calls, 1)
}

@(test)
given_cache_poll_error_with_progress_when_polled_through_binding_then_both_results_are_forwarded :: proc(t: ^testing.T) {
	// Arrange
	spy := C_Binding_Cache_Spy{progress = true, err = .FileOperationError}
	log: rifle.Log
	c_binding_test_log(&log, &spy)
	progress := false

	// Act
	err := rifle_log_poll(&log, &progress)

	// Assert
	testing.expect_value(t, err, rifle.RifleError.FileOperationError)
	testing.expect(t, progress)
	testing.expect_value(t, spy.poll_calls, 1)
}

when size_of(rawptr) == 8 {
	#assert(size_of(rifle.LogConfig) == 88)
	#assert(align_of(rifle.LogConfig) == 8)
	#assert(offset_of(rifle.LogConfig, schema) == 64)
	#assert(size_of(rifle.RecordSchema) == 24)
	#assert(offset_of(rifle.RecordSchema, fields) == 8)
	#assert(size_of(rifle.SchemaField) == 40)
	#assert(offset_of(rifle.SchemaField, type) == 16)
	#assert(offset_of(rifle.SchemaField, offset) == 24)
	#assert(offset_of(rifle.SchemaField, size) == 32)
	#assert(align_of(rifle.Log) == 128)
	#assert(offset_of(rifle.Log, config) == 640)
}
