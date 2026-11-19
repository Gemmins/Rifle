package e2e

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:thread"
import "core:time"
import rifle "rifle:rifle"

E2E_Log :: struct {
	log:       ^rifle.Log,
	directory: string,
	path:      cstring,
	base:      string,
	base_path: cstring,
}

e2e_log_cleanup :: proc(ctx: rawptr) {
	fixture := cast(^E2E_Log)ctx
	if fixture.log != nil {
		_ = rifle.log_deinit(fixture.log)
	}
	if len(fixture.directory) > 0 {
		_ = os.remove_all(fixture.directory)
	}
	delete(fixture.base_path)
	delete(fixture.base)
	delete(fixture.path)
	delete(fixture.directory)
	free(fixture)
}

e2e_log_config :: proc(path: cstring, schema: rifle.RecordSchema) -> rifle.LogConfig {
	config := rifle.DefaultLogConfig
	config.log_path = path
	config.ring_size_bytes = 1 << 16
	config.page_cache_size_bytes = 4 * 4096
	config.file_size_bytes = 2 * 4096
	config.page_size_bytes = 4096
	config.max_open_files = 8
	config.commit_ring_size = 64
	config.schema = schema
	return config
}

e2e_log_fixture :: proc(t: ^testing.T) -> ^E2E_Log {
	testing.set_fail_timeout(t, 20 * time.Second)
	fixture := new(E2E_Log)
	testing.cleanup(t, e2e_log_cleanup, fixture)
	directory, directory_err := os.make_directory_temp("/tmp", "rifle-e2e-*", context.allocator)
	if !testing.expect(t, directory_err == nil) {
		testing.fail_now(t)
	}
	fixture.directory = directory
	fixture.path = strings.clone_to_cstring(directory)
	fixture.base = strings.concatenate({directory, "/", rifle.BASE_FILENAME})
	fixture.base_path = strings.clone_to_cstring(fixture.base)
	return fixture
}

e2e_log_create :: proc(t: ^testing.T) -> ^E2E_Log {
	fixture := e2e_log_fixture(t)
	fields := []rifle.SchemaField{{name = "value", type = .I64}}
	config := e2e_log_config(fixture.path, {record_size = 8, fields = fields})
	log, init_err := rifle.log_init(config, nil)
	if !testing.expect_value(t, init_err, rifle.RifleError.None) {
		testing.fail_now(t)
	}
	fixture.log = log
	return fixture
}

e2e_sync :: proc(t: ^testing.T, log: ^rifle.Log) {
	target := rifle.log_sync(log)
	for _ in 0 ..< 100000 {
		if log.durable_index.value >= target {
			return
		}
		_, err := rifle.log_poll(log)
		cache := cast(^rifle.RecordCache)log.cache.data
		if !testing.expectf(
			t,
			err == nil,
			"sync poll failed: error=%v target=%d visible=%d persisted=%d durable=%d writing_byte=%d persisted_byte=%d writes=%d write_head=%d write_failed=%v sync_pending=%v sync_in_progress=%v write_slots=%v",
			err,
			target,
			log.visible_index.value,
			log.persisted_index.value,
			log.durable_index.value,
			cache.writing_byte_index,
			cache.persisted_byte_index,
			cache.write_count,
			cache.write_head,
			cache.write_failed,
			cache.sync_pending,
			cache.sync_in_progress,
			cache.writes[:4],
		) {
			testing.fail_now(t)
		}
	}
	cache := cast(^rifle.RecordCache)log.cache.data
	testing.expectf(
		t,
		false,
		"sync stalled: target=%d visible=%d persisted=%d durable=%d writing_byte=%d persisted_byte=%d writes=%d write_head=%d write_failed=%v sync_pending=%v sync_in_progress=%v",
		target,
		log.visible_index.value,
		log.persisted_index.value,
		log.durable_index.value,
		cache.writing_byte_index,
		cache.persisted_byte_index,
		cache.write_count,
		cache.write_head,
		cache.write_failed,
		cache.sync_pending,
		cache.sync_in_progress,
	)
	testing.fail_now(t)
}

e2e_wait_for_files_removed :: proc(t: ^testing.T, log: ^rifle.Log, first, second: string) {
	for _ in 0 ..< 100000 {
		if !os.exists(first) && !os.exists(second) {
			return
		}
		_, err := rifle.log_poll(log)
		if !testing.expect_value(t, err, rifle.RifleError.None) {
			testing.fail_now(t)
		}
	}
	testing.expect(t, false)
	testing.fail_now(t)
}

@(test)
given_new_log_when_records_cross_cache_and_file_boundaries_then_data_persists_reopens_and_drops :: proc(t: ^testing.T) {
	// Arrange
	fixture := e2e_log_create(t)
	input: [4096]i64
	for &value, i in input {
		value = i64(i + 1)
	}
	input_bytes := (cast([^]u8)raw_data(input[:]))[:size_of(input)]

	// Act
	index, write_err := rifle.log_write(fixture.log, input_bytes, len(input))
	e2e_sync(t, fixture.log)
	first_read: [4096]i64
	first_read_bytes := (cast([^]u8)raw_data(first_read[:]))[:size_of(first_read)]
	first_read_err := rifle.log_read(fixture.log, first_read_bytes, 0, len(first_read))
	close_err := rifle.log_deinit(fixture.log)
	fixture.log = nil
	reopen_config := e2e_log_config(fixture.path, {})
	reopened, reopen_err := rifle.log_init(reopen_config, fixture.base_path)
	if !testing.expect_value(t, reopen_err, rifle.RifleError.None) {
		return
	}
	fixture.log = reopened
	second_read: [2048]i64
	second_read_bytes := (cast([^]u8)raw_data(second_read[:]))[:size_of(second_read)]
	second_read_err := rifle.log_read(reopened, second_read_bytes, 2048, len(second_read))
	drop_err := rifle.log_drop(reopened, 2048)
	first_file := fmt.aprintf("%s/data_%020d.rfl", fixture.directory, 0)
	defer delete(first_file)
	second_file := fmt.aprintf("%s/data_%020d.rfl", fixture.directory, 1)
	defer delete(second_file)
	e2e_wait_for_files_removed(t, reopened, first_file, second_file)
	e2e_sync(t, reopened)
	below_drop_err := rifle.log_read(reopened, second_read_bytes[:8], 0, 1)
	metadata, metadata_err := rifle.read_base_file(fixture.base_path)
	defer rifle.schema_destroy(metadata.schema)

	// Assert
	testing.expect_value(t, write_err, rifle.RifleError.None)
	testing.expect_value(t, index, i64(0))
	testing.expect_value(t, fixture.log.visible_index.value, i64(4096))
	testing.expect_value(t, fixture.log.persisted_index.value, i64(4096))
	testing.expect_value(t, fixture.log.durable_index.value, i64(4096))
	testing.expect_value(t, first_read_err, rifle.RifleError.None)
	testing.expect_value(t, first_read, input)
	testing.expect_value(t, close_err, rifle.RifleError.None)
	testing.expect_value(t, second_read_err, rifle.RifleError.None)
	for value, i in second_read {
		testing.expect_value(t, value, i64(2049 + i))
	}
	testing.expect_value(t, drop_err, rifle.RifleError.None)
	testing.expect_value(t, below_drop_err, rifle.RifleError.IndexOutOfBoundsError)
	testing.expect_value(t, fixture.log.trailing_index.value, i64(2048))
	testing.expect_value(t, metadata_err, rifle.RifleError.None)
	testing.expect_value(t, metadata.head, i64(4096))
	testing.expect_value(t, metadata.tail, i64(2048))
}

E2E_Writer :: struct {
	log:     ^rifle.Log,
	id:      int,
	barrier: ^sync.Barrier,
	index:   i64,
	err:     rifle.RifleError,
}

e2e_write_records :: proc(worker_thread: ^thread.Thread) {
	worker := cast(^E2E_Writer)worker_thread.data
	data: [512]i64
	for &value, i in data {
		value = (i64(worker.id) << 32) | i64(i)
	}
	bytes := (cast([^]u8)raw_data(data[:]))[:size_of(data)]
	sync.barrier_wait(worker.barrier)
	worker.index, worker.err = rifle.log_write(worker.log, bytes, len(data))
}

@(test)
given_concurrent_writers_when_batches_are_appended_then_every_reserved_range_is_visible_and_durable :: proc(t: ^testing.T) {
	// Arrange
	fixture := e2e_log_create(t)
	barrier: sync.Barrier
	sync.barrier_init(&barrier, 4)
	writers: [4]E2E_Writer
	threads: [4]^thread.Thread
	for &writer, i in writers {
		writer = {log = fixture.log, id = i, barrier = &barrier}
		threads[i] = thread.create(e2e_write_records)
		threads[i].data = &writer
	}

	// Act
	for worker_thread in threads {
		thread.start(worker_thread)
	}
	for worker_thread in threads {
		thread.join(worker_thread)
		thread.destroy(worker_thread)
	}
	e2e_sync(t, fixture.log)
	ranges_seen: [4]bool
	contents_match := true
	for writer in writers {
		if writer.index < 0 || writer.index % 512 != 0 || writer.index >= 2048 {
			contents_match = false
			continue
		}
		ranges_seen[writer.index / 512] = true
		output: [512]i64
		output_bytes := (cast([^]u8)raw_data(output[:]))[:size_of(output)]
		if rifle.log_read(fixture.log, output_bytes, writer.index, len(output)) != nil {
			contents_match = false
			continue
		}
		for value, i in output {
			contents_match = contents_match && value == ((i64(writer.id) << 32) | i64(i))
		}
	}

	// Assert
	for writer in writers {
		testing.expect_value(t, writer.err, rifle.RifleError.None)
	}
	for seen in ranges_seen {
		testing.expect(t, seen)
	}
	testing.expect(t, contents_match)
	testing.expect_value(t, fixture.log.commited_index.value, i64(2048))
	testing.expect_value(t, fixture.log.visible_index.value, i64(2048))
	testing.expect_value(t, fixture.log.persisted_index.value, i64(2048))
	testing.expect_value(t, fixture.log.durable_index.value, i64(2048))
}

E2E_Wide_Record :: struct {
	first:  i64,
	second: i64,
	third:  i64,
}

@(test)
given_non_power_of_two_record_file_and_batch_sizes_when_partial_tail_is_synced_then_every_record_persists_and_reopens :: proc(t: ^testing.T) {
	// Arrange
	fixture := e2e_log_fixture(t)
	fields := []rifle.SchemaField{
		{name = "first", type = .I64, offset = 0},
		{name = "second", type = .I64, offset = 8},
		{name = "third", type = .I64, offset = 16},
	}
	config := e2e_log_config(fixture.path, {record_size = size_of(E2E_Wide_Record), fields = fields})
	config.page_cache_size_bytes = 16 * 4096
	config.file_size_bytes = 3 * 4096
	config.max_open_files = 7
	config.read_chunk_size = 3
	log, init_err := rifle.log_init(config, nil)
	if !testing.expect_value(t, init_err, rifle.RifleError.None) {
		return
	}
	fixture.log = log
	input: [777]E2E_Wide_Record
	for &record, i in input {
		record = {i64(i + 1), i64(i * 3 + 2), -i64(i + 7)}
	}
	input_bytes := (cast([^]u8)raw_data(input[:]))[:size_of(input)]

	// Act
	index, write_err := rifle.log_write(log, input_bytes, len(input))
	e2e_sync(t, log)
	first_read: [len(input)]E2E_Wide_Record
	first_read_bytes := (cast([^]u8)raw_data(first_read[:]))[:size_of(first_read)]
	first_read_err := rifle.log_read(log, first_read_bytes, 0, len(first_read))
	close_err := rifle.log_deinit(log)
	fixture.log = nil
	config.schema = {}
	reopened, reopen_err := rifle.log_init(config, fixture.base_path)
	if !testing.expect_value(t, reopen_err, rifle.RifleError.None) {
		return
	}
	fixture.log = reopened
	second_read: [len(input)]E2E_Wide_Record
	second_read_bytes := (cast([^]u8)raw_data(second_read[:]))[:size_of(second_read)]
	second_read_err := rifle.log_read(reopened, second_read_bytes, 0, len(second_read))
	metadata, metadata_err := rifle.read_base_file(fixture.base_path)
	defer rifle.schema_destroy(metadata.schema)

	// Assert
	testing.expect_value(t, size_of(E2E_Wide_Record), 24)
	testing.expect_value(t, write_err, rifle.RifleError.None)
	testing.expect_value(t, index, i64(0))
	testing.expect_value(t, first_read_err, rifle.RifleError.None)
	testing.expect_value(t, first_read, input)
	testing.expect_value(t, close_err, rifle.RifleError.None)
	testing.expect_value(t, reopen_err, rifle.RifleError.None)
	testing.expect_value(t, second_read_err, rifle.RifleError.None)
	testing.expect_value(t, second_read, input)
	testing.expect_value(t, reopened.config.file_size_bytes, i64(3 * 4096))
	testing.expect_value(t, reopened.config.max_open_files, u16(7))
	testing.expect_value(t, reopened.config.read_chunk_size, i64(3))
	testing.expect_value(t, metadata_err, rifle.RifleError.None)
	testing.expect_value(t, metadata.head, i64(len(input)))
	testing.expect_value(t, metadata.tail, i64(0))
}
