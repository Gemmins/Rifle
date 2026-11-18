package unit

import "base:runtime"
import "core:sync"
import "core:sys/linux"
import "core:sys/posix"
import "core:testing"
import "core:thread"
import "core:time"
import rifle "rifle:rifle"

CACHE_TEST_RING_SIZE :: i64(16384)
CACHE_TEST_PAGE_SIZE :: i64(4096)
CACHE_TEST_PAGE_CAPACITY :: i64(16384)
CACHE_TEST_FILE_SIZE :: i64(8192)
CACHE_TEST_RECORD_SIZE :: i64(8)
CACHE_TEST_COMMIT_RING_SIZE :: i64(8)

Cache_Test_IO_Request :: struct {
	user_data: rifle.IOUserData,
	file_id:   i64,
	buffer:    []u8,
	offset:    u64,
}

Cache_Test_IO :: struct {
	requests:           [256]Cache_Test_IO_Request,
	request_count:      int,
	completions:        [256]rifle.IOCompletion,
	completion_count:   int,
	buffers:            [2][]u8,
	read_source:        [CACHE_TEST_FILE_SIZE]u8,
	auto_complete_reads: bool,
	initialized:        bool,
	deinitialized:      bool,
	next_error:         rifle.RifleError,
	poll_error:         rifle.RifleError,
	poll_calls:         i64,
}

cache_test_io_queue :: proc(
	fake: ^Cache_Test_IO,
	user_data: rifle.IOUserData,
	file_id: i64 = 0,
	buffer: []u8 = nil,
	offset: u64 = 0,
) -> rifle.RifleError {
	if fake.next_error != nil {
		err := fake.next_error
		fake.next_error = nil
		return err
	}
	if fake.request_count == len(fake.requests) {
		return .GenericError
	}
	fake.requests[fake.request_count] = {user_data, file_id, buffer, offset}
	fake.request_count += 1
	return nil
}

cache_test_io_complete :: proc(fake: ^Cache_Test_IO, index: int, result: i32) {
	assert(index >= 0 && index < fake.request_count)
	request := fake.requests[index]
	if request.user_data.op == .READ && result > 0 {
		start := int(request.offset)
		copy(request.buffer[:result], fake.read_source[start:start + int(result)])
	}
	fake.completions[fake.completion_count] = {user_data = request.user_data, res = result}
	fake.completion_count += 1
	for i in index ..< fake.request_count - 1 {
		fake.requests[i] = fake.requests[i + 1]
	}
	fake.request_count -= 1
}

cache_test_io_find :: proc(fake: ^Cache_Test_IO, operation: rifle.IOOperation) -> int {
	for request, i in fake.requests[:fake.request_count] {
		if request.user_data.op == operation {
			return i
		}
	}
	return -1
}

cache_test_io_interface :: proc(fake: ^Cache_Test_IO) -> rifle.IO {
	return {
		data = fake,
		init = proc(ctx: rawptr, buffers: [][]u8) -> rifle.RifleError {
			fake := cast(^Cache_Test_IO)ctx
			copy(fake.buffers[:], buffers)
			fake.initialized = true
			return nil
		},
		deinit = proc(ctx: rawptr) -> rifle.RifleError {
			fake := cast(^Cache_Test_IO)ctx
			fake.deinitialized = true
			return nil
		},
		open = proc(ctx: rawptr, data: rifle.IOUserData, file_id: i64) -> rifle.RifleError {
			return cache_test_io_queue(cast(^Cache_Test_IO)ctx, data, file_id)
		},
		close = proc(ctx: rawptr, data: rifle.IOUserData, file_id: i64) -> rifle.RifleError {
			return cache_test_io_queue(cast(^Cache_Test_IO)ctx, data, file_id)
		},
		read_at = proc(ctx: rawptr, data: rifle.IOUserData, buffer: []u8, offset: u64, file_id: i64) -> rifle.RifleError {
			fake := cast(^Cache_Test_IO)ctx
			err := cache_test_io_queue(fake, data, file_id, buffer, offset)
			if err == nil && fake.auto_complete_reads {
				cache_test_io_complete(fake, fake.request_count - 1, i32(len(buffer)))
			}
			return err
		},
		write_at = proc(ctx: rawptr, data: rifle.IOUserData, buffer: []u8, offset: u64, file_id: i64) -> rifle.RifleError {
			return cache_test_io_queue(cast(^Cache_Test_IO)ctx, data, file_id, buffer, offset)
		},
		write_header = proc(ctx: rawptr, data: rifle.IOUserData, buffer: []u8) -> rifle.RifleError {
			return cache_test_io_queue(cast(^Cache_Test_IO)ctx, data, buffer = buffer)
		},
		sync = proc(ctx: rawptr, data: rifle.IOUserData) -> rifle.RifleError {
			return cache_test_io_queue(cast(^Cache_Test_IO)ctx, data)
		},
		unlink = proc(ctx: rawptr, data: rifle.IOUserData, file_id: i64) -> rifle.RifleError {
			return cache_test_io_queue(cast(^Cache_Test_IO)ctx, data, file_id)
		},
		poll = proc(ctx: rawptr, output: []rifle.IOCompletion) -> (u32, rifle.RifleError) {
			fake := cast(^Cache_Test_IO)ctx
			sync.atomic_add(&fake.poll_calls, 1)
			if fake.poll_error != nil {
				err := fake.poll_error
				fake.poll_error = nil
				return 0, err
			}
			count := min(len(output), fake.completion_count)
			copy(output, fake.completions[:count])
			for i in count ..< fake.completion_count {
				fake.completions[i - count] = fake.completions[i]
			}
			fake.completion_count -= count
			return u32(count), nil
		},
	}
}

Cache_Test_Write_Worker :: struct {
	cache:   rifle.Cache,
	entered: ^sync.Sema,
	data:    [1]i64,
	err:     rifle.RifleError,
}

cache_test_write_out_of_order :: proc(worker_thread: ^thread.Thread) {
	worker := cast(^Cache_Test_Write_Worker)worker_thread.data
	bytes := (cast([^]u8)raw_data(worker.data[:]))[:size_of(worker.data)]
	sync.sema_post(worker.entered)
	worker.err = worker.cache.write(worker.cache.data, bytes, 8, 1)
}

Cache_Test_Arena :: struct {
	arena: rifle.FileBackedArena,
}

Cache_Test_Fixture :: struct {
	original_allocator: runtime.Allocator,
	fd:                 linux.Fd,
	owner:              ^Cache_Test_Arena,
	cache:              rifle.Cache,
	fake:               Cache_Test_IO,
	visible:            i64,
	persisted:          i64,
	durable:            i64,
	dropped:            i64,
	initialized:        bool,
}

cache_test_cleanup :: proc(ctx: rawptr) {
	fixture := cast(^Cache_Test_Fixture)ctx
	context.allocator = fixture.original_allocator
	if fixture.initialized {
		_ = fixture.cache.deinit(fixture.cache.data)
	}
	if fixture.owner != nil {
		_ = rifle.destroy_file_backed_arena(&fixture.owner.arena)
	}
	if fixture.fd >= 0 {
		_ = linux.close(fixture.fd)
	}
	free(fixture)
}

cache_test_setup :: proc(t: ^testing.T) -> ^Cache_Test_Fixture {
	fixture := new(Cache_Test_Fixture)
	fixture.original_allocator = context.allocator
	fixture.fd = -1
	testing.cleanup(t, cache_test_cleanup, fixture)
	fd, create_err := linux.memfd_create("rifle-record-cache-test", {.CLOEXEC})
	if !testing.expect_value(t, create_err, linux.Errno.NONE) {
		testing.fail_now(t)
	}
	fixture.fd = fd
	page_size := i64(posix.sysconf(._PAGE_SIZE))
	required := i64(size_of(Cache_Test_Arena)) + rifle.record_cache_arena_size(
		CACHE_TEST_RING_SIZE,
		CACHE_TEST_PAGE_CAPACITY,
		CACHE_TEST_PAGE_SIZE,
		CACHE_TEST_COMMIT_RING_SIZE,
	) + page_size
	arena_size := (required + page_size - 1) & ~(page_size - 1)
	owner, arena_err := rifle.file_backed_arena_bootstrap_by_name(Cache_Test_Arena, "arena", fd, arena_size)
	if !testing.expect_value(t, arena_err, rifle.RifleError.None) {
		testing.fail_now(t)
	}
	fixture.owner = owner
	context.allocator = {owner.arena.allocator_proc, &owner.arena}
	fixture.cache = rifle.new_record_cache()
	err := fixture.cache.init(
		fixture.cache.data,
		CACHE_TEST_RING_SIZE,
		CACHE_TEST_PAGE_CAPACITY,
		CACHE_TEST_PAGE_SIZE,
		CACHE_TEST_COMMIT_RING_SIZE,
		cache_test_io_interface(&fixture.fake),
		CACHE_TEST_FILE_SIZE,
		CACHE_TEST_RECORD_SIZE,
		&fixture.visible,
		&fixture.persisted,
		&fixture.durable,
		&fixture.dropped,
	)
	if !testing.expect_value(t, err, rifle.RifleError.None) {
		testing.fail_now(t)
	}
	fixture.initialized = true
	return fixture
}

@(test)
given_valid_configuration_when_record_cache_is_initialized_then_storage_and_io_are_wired :: proc(t: ^testing.T) {
	// Arrange
	fixture := cache_test_setup(t)

	// Act
	cache := cast(^rifle.RecordCache)fixture.cache.data

	// Assert
	testing.expect(t, fixture.fake.initialized)
	testing.expect_value(t, len(cache.pages), 4)
	testing.expect_value(t, len(cache.sets), 1)
	testing.expect_value(t, len(cache.commit_ring), 8)
	testing.expect_value(t, cache.page_size, CACHE_TEST_PAGE_SIZE)
	testing.expect_value(t, cache.record_size, CACHE_TEST_RECORD_SIZE)
	testing.expect_value(t, cache.file_size, CACHE_TEST_FILE_SIZE)
	testing.expect(t, cache.visible_index == &fixture.visible)
	testing.expect(t, cache.persisted_index == &fixture.persisted)
	testing.expect(t, cache.durable_index == &fixture.durable)
	testing.expect(t, cache.dropped_index == &fixture.dropped)
	testing.expect(t, raw_data(fixture.fake.buffers[0]) == raw_data(cache.pages[0].data))
	testing.expect(t, raw_data(fixture.fake.buffers[1]) == raw_data(cache.header_data))
	for entry in cache.commit_ring {
		testing.expect_value(t, entry.value, i64(-1))
	}
}

@(test)
given_records_when_written_then_bytes_are_copied_and_visibility_advances :: proc(t: ^testing.T) {
	// Arrange
	fixture := cache_test_setup(t)
	cache := cast(^rifle.RecordCache)fixture.cache.data
	data: [1024]i64
	for &value, i in data {
		value = i64(i + 1)
	}
	bytes := (cast([^]u8)raw_data(data[:]))[:size_of(data)]

	// Act
	err := fixture.cache.write(fixture.cache.data, bytes, 0, len(data))

	// Assert
	testing.expect_value(t, err, rifle.RifleError.None)
	testing.expect_value(t, fixture.visible, i64(1024))
	testing.expect_value(t, fixture.persisted, i64(0))
	testing.expect_value(t, string(cache.ring_data[:len(bytes)]), string(bytes))
}

@(test)
given_write_crossing_ring_end_when_written_then_double_mapping_preserves_contiguous_bytes :: proc(t: ^testing.T) {
	// Arrange
	fixture := cache_test_setup(t)
	cache := cast(^rifle.RecordCache)fixture.cache.data
	fixture.visible = 2040
	fixture.persisted = 2040
	data: [16]i64
	for &value, i in data {
		value = i64(100 + i)
	}
	bytes := (cast([^]u8)raw_data(data[:]))[:size_of(data)]
	offset := 2040 * CACHE_TEST_RECORD_SIZE

	// Act
	err := fixture.cache.write(fixture.cache.data, bytes, 2040, len(data))

	// Assert
	testing.expect_value(t, err, rifle.RifleError.None)
	testing.expect_value(t, fixture.visible, i64(2056))
	testing.expect_value(t, string(cache.ring_data[offset:offset + i64(len(bytes))]), string(bytes))
}

@(test)
given_visible_full_pages_when_polled_and_write_completes_then_persisted_index_advances :: proc(t: ^testing.T) {
	// Arrange
	fixture := cache_test_setup(t)
	data: [1024]i64
	bytes := (cast([^]u8)raw_data(data[:]))[:size_of(data)]
	write_err := fixture.cache.write(fixture.cache.data, bytes, 0, len(data))
	if !testing.expect_value(t, write_err, rifle.RifleError.None) {
		return
	}

	// Act
	_, first_poll_err := fixture.cache.poll(fixture.cache.data)
	write_request := cache_test_io_find(&fixture.fake, .WRITE)
	header_request := cache_test_io_find(&fixture.fake, .HEADER)
	if write_request >= 0 {
		cache_test_io_complete(&fixture.fake, write_request, i32(size_of(data)))
	}
	header_request = cache_test_io_find(&fixture.fake, .HEADER)
	if header_request >= 0 {
		cache_test_io_complete(&fixture.fake, header_request, 16)
	}
	_, completion_err := fixture.cache.poll(fixture.cache.data)

	// Assert
	testing.expect_value(t, first_poll_err, rifle.RifleError.None)
	testing.expect(t, write_request >= 0)
	testing.expect_value(t, completion_err, rifle.RifleError.None)
	testing.expect_value(t, fixture.persisted, i64(1024))
}

@(test)
given_persisted_visible_records_when_sync_completes_then_durable_index_advances :: proc(t: ^testing.T) {
	// Arrange
	fixture := cache_test_setup(t)
	cache := cast(^rifle.RecordCache)fixture.cache.data
	fixture.visible = 512
	fixture.persisted = 512
	cache.writing_byte_index = 4096
	cache.persisted_byte_index = 4096
	fixture.cache.sync(fixture.cache.data)

	// Act
	_, first_poll_err := fixture.cache.poll(fixture.cache.data)
	sync_request := cache_test_io_find(&fixture.fake, .SYNC)
	if sync_request >= 0 {
		cache_test_io_complete(&fixture.fake, sync_request, 0)
	}
	header_request := cache_test_io_find(&fixture.fake, .HEADER)
	if header_request >= 0 {
		cache_test_io_complete(&fixture.fake, header_request, 16)
	}
	_, completion_err := fixture.cache.poll(fixture.cache.data)

	// Assert
	testing.expect_value(t, first_poll_err, rifle.RifleError.None)
	testing.expect(t, sync_request >= 0)
	testing.expect_value(t, completion_err, rifle.RifleError.None)
	testing.expect_value(t, fixture.durable, i64(512))
	testing.expect(t, !cache.sync_in_progress)
}

@(test)
given_persisted_and_unpersisted_records_when_read_then_disk_and_ring_data_are_combined :: proc(t: ^testing.T) {
	// Arrange
	fixture := cache_test_setup(t)
	cache := cast(^rifle.RecordCache)fixture.cache.data
	fixture.fake.auto_complete_reads = true
	fixture.visible = 10
	fixture.persisted = 5
	for i in 0 ..< 5 {
		(cast([^]i64)raw_data(fixture.fake.read_source[:]))[i] = i64(100 + i)
	}
	for i in 5 ..< 10 {
		(cast([^]i64)raw_data(cache.ring_data))[i] = i64(100 + i)
	}
	output: [7]i64
	output_bytes := (cast([^]u8)raw_data(output[:]))[:size_of(output)]

	// Act
	err := fixture.cache.read(fixture.cache.data, output_bytes, 3, 7)
	page_loaded := false
	for page in cache.pages {
		if page.index == 0 && page.state == .Clean {
			page_loaded = true
		}
	}

	// Assert
	testing.expect_value(t, err, rifle.RifleError.None)
	for value, i in output {
		testing.expect_value(t, value, i64(103 + i))
	}
	testing.expect(t, page_loaded)
}

@(test)
given_dropped_whole_files_when_polled_then_each_file_is_unlinked_and_missing_files_are_accepted :: proc(t: ^testing.T) {
	// Arrange
	fixture := cache_test_setup(t)
	fixture.dropped = 2048

	// Act
	_, first_poll_err := fixture.cache.poll(fixture.cache.data)
	first_delete := cache_test_io_find(&fixture.fake, .DELETE)
	first_file := first_delete >= 0 ? fixture.fake.requests[first_delete].file_id : -1
	if first_delete >= 0 {
		cache_test_io_complete(&fixture.fake, first_delete, 0)
	}
	second_delete := cache_test_io_find(&fixture.fake, .DELETE)
	second_file := second_delete >= 0 ? fixture.fake.requests[second_delete].file_id : -1
	if second_delete >= 0 {
		cache_test_io_complete(&fixture.fake, second_delete, -i32(linux.Errno.ENOENT))
	}
	header_request := cache_test_io_find(&fixture.fake, .HEADER)
	if header_request >= 0 {
		cache_test_io_complete(&fixture.fake, header_request, 16)
	}
	_, completion_err := fixture.cache.poll(fixture.cache.data)

	// Assert
	testing.expect_value(t, first_poll_err, rifle.RifleError.None)
	testing.expect_value(t, first_file, i64(0))
	testing.expect_value(t, second_file, i64(1))
	testing.expect_value(t, completion_err, rifle.RifleError.None)
	testing.expect_value(t, fixture.persisted, i64(2048))
	testing.expect_value(t, fixture.durable, i64(2048))
}

@(test)
given_short_data_write_when_completion_is_polled_then_file_operation_error_is_returned :: proc(t: ^testing.T) {
	// Arrange
	fixture := cache_test_setup(t)
	cache := cast(^rifle.RecordCache)fixture.cache.data
	data: [512]i64
	bytes := (cast([^]u8)raw_data(data[:]))[:size_of(data)]
	write_err := fixture.cache.write(fixture.cache.data, bytes, 0, len(data))
	if !testing.expect_value(t, write_err, rifle.RifleError.None) {
		return
	}
	_, first_poll_err := fixture.cache.poll(fixture.cache.data)
	if !testing.expect_value(t, first_poll_err, rifle.RifleError.None) {
		return
	}
	write_request := cache_test_io_find(&fixture.fake, .WRITE)
	if write_request >= 0 {
		cache_test_io_complete(&fixture.fake, write_request, 2048)
	}

	// Act
	_, err := fixture.cache.poll(fixture.cache.data)

	// Assert
	testing.expect(t, write_request >= 0)
	testing.expect_value(t, err, rifle.RifleError.FileOperationError)
	testing.expect(t, !cache.write_failed)
	testing.expect_value(t, cache.writing_byte_index, i64(0))
	testing.expect_value(t, fixture.persisted, i64(0))
}

@(test)
given_out_of_order_writer_waiting_for_visibility_when_earlier_writer_completes_then_no_io_is_polled :: proc(t: ^testing.T) {
	// Arrange
	fixture := cache_test_setup(t)
	entered: sync.Sema
	worker := Cache_Test_Write_Worker{cache = fixture.cache, entered = &entered, data = {9}}
	worker_thread := thread.create(cache_test_write_out_of_order)
	worker_thread.data = &worker
	first: [8]i64
	for &value, i in first {
		value = i64(i + 1)
	}
	first_bytes := (cast([^]u8)raw_data(first[:]))[:size_of(first)]

	// Act
	thread.start(worker_thread)
	if !testing.expect(t, sync.sema_wait_with_timeout(&entered, time.Second)) {
		thread.join(worker_thread)
		thread.destroy(worker_thread)
		return
	}
	time.sleep(5 * time.Millisecond)
	poll_calls_while_waiting := sync.atomic_load(&fixture.fake.poll_calls)
	first_err := fixture.cache.write(fixture.cache.data, first_bytes, 0, 8)
	thread.join(worker_thread)
	thread.destroy(worker_thread)

	// Assert
	testing.expect_value(t, poll_calls_while_waiting, i64(0))
	testing.expect_value(t, first_err, rifle.RifleError.None)
	testing.expect_value(t, worker.err, rifle.RifleError.None)
	testing.expect_value(t, fixture.visible, i64(9))
	cache := cast(^rifle.RecordCache)fixture.cache.data
	values := cast([^]i64)raw_data(cache.ring_data)
	for value, i in first {
		testing.expect_value(t, values[i], value)
	}
	testing.expect_value(t, values[8], i64(9))
}

@(test)
given_zero_record_ranges_when_read_or_written_then_cache_state_and_io_remain_unchanged :: proc(t: ^testing.T) {
	// Arrange
	fixture := cache_test_setup(t)
	fixture.visible = 4
	fixture.persisted = 4
	output := [8]u8{1, 2, 3, 4, 5, 6, 7, 8}

	// Act
	read_err := fixture.cache.read(fixture.cache.data, output[:], 4, 0)
	write_err := fixture.cache.write(fixture.cache.data, nil, 4, 0)

	// Assert
	testing.expect_value(t, read_err, rifle.RifleError.None)
	testing.expect_value(t, write_err, rifle.RifleError.None)
	testing.expect_value(t, output, [8]u8{1, 2, 3, 4, 5, 6, 7, 8})
	testing.expect_value(t, fixture.visible, i64(4))
	testing.expect_value(t, fixture.persisted, i64(4))
	testing.expect_value(t, fixture.fake.request_count, 0)
	testing.expect_value(t, sync.atomic_load(&fixture.fake.poll_calls), i64(0))
}

@(test)
given_another_cache_poller_is_active_when_polled_then_io_is_not_entered :: proc(t: ^testing.T) {
	// Arrange
	fixture := cache_test_setup(t)
	cache := cast(^rifle.RecordCache)fixture.cache.data
	sync.atomic_store(&cache.polling, 1)

	// Act
	polled, err := fixture.cache.poll(fixture.cache.data)

	// Assert
	testing.expect(t, !polled)
	testing.expect_value(t, err, rifle.RifleError.None)
	testing.expect_value(t, sync.atomic_load(&fixture.fake.poll_calls), i64(0))
	testing.expect_value(t, sync.atomic_load(&cache.polling), u32(1))
}

@(test)
given_short_page_read_completion_when_polled_then_page_is_retryable_and_error_is_returned :: proc(t: ^testing.T) {
	// Arrange
	fixture := cache_test_setup(t)
	cache := cast(^rifle.RecordCache)fixture.cache.data
	cache.pages[0].index = 0
	cache.pages[0].file_id = 0
	cache.pages[0].ref_count = 1
	cache.pages[0].state = .Loading
	fixture.fake.completions[0] = {user_data = {op = .READ, page_index = 0}, res = 2048}
	fixture.fake.completion_count = 1

	// Act
	polled, err := fixture.cache.poll(fixture.cache.data)

	// Assert
	testing.expect(t, polled)
	testing.expect_value(t, err, rifle.RifleError.FileOperationError)
	testing.expect_value(t, cache.pages[0].state, rifle.RecordCachePageState.Read_Pending)
	testing.expect_value(t, cache.pages[0].ref_count, i64(1))
}

@(test)
given_short_header_write_completion_when_polled_then_header_is_retryable_and_error_is_returned :: proc(t: ^testing.T) {
	// Arrange
	fixture := cache_test_setup(t)
	_, queue_err := fixture.cache.poll(fixture.cache.data)
	header_request := cache_test_io_find(&fixture.fake, .HEADER)
	if header_request >= 0 {
		cache_test_io_complete(&fixture.fake, header_request, 8)
	}

	// Act
	_, err := fixture.cache.poll(fixture.cache.data)
	cache := cast(^rifle.RecordCache)fixture.cache.data

	// Assert
	testing.expect_value(t, queue_err, rifle.RifleError.None)
	testing.expect(t, header_request >= 0)
	testing.expect_value(t, err, rifle.RifleError.FileOperationError)
	testing.expect(t, !cache.header_in_progress)
}

@(test)
given_failed_sync_completion_when_polled_then_sync_is_requeued_and_durability_does_not_advance :: proc(t: ^testing.T) {
	// Arrange
	fixture := cache_test_setup(t)
	cache := cast(^rifle.RecordCache)fixture.cache.data
	fixture.visible = 512
	fixture.persisted = 512
	cache.writing_byte_index = 4096
	cache.persisted_byte_index = 4096
	fixture.cache.sync(fixture.cache.data)
	_, queue_err := fixture.cache.poll(fixture.cache.data)
	sync_request := cache_test_io_find(&fixture.fake, .SYNC)
	if sync_request >= 0 {
		cache_test_io_complete(&fixture.fake, sync_request, -i32(linux.Errno.EIO))
	}
	header_request := cache_test_io_find(&fixture.fake, .HEADER)
	if header_request >= 0 {
		cache_test_io_complete(&fixture.fake, header_request, 16)
	}

	// Act
	_, err := fixture.cache.poll(fixture.cache.data)

	// Assert
	testing.expect_value(t, queue_err, rifle.RifleError.None)
	testing.expect(t, sync_request >= 0)
	testing.expect_value(t, err, rifle.RifleError.FileOperationError)
	testing.expect(t, cache.sync_pending)
	testing.expect(t, !cache.sync_in_progress)
	testing.expect_value(t, fixture.durable, i64(0))
}

@(test)
given_out_of_order_data_write_completions_when_polled_then_only_contiguous_prefix_is_persisted :: proc(t: ^testing.T) {
	// Arrange
	fixture := cache_test_setup(t)
	data: [2048]i64
	bytes := (cast([^]u8)raw_data(data[:]))[:size_of(data)]
	write_err := fixture.cache.write(fixture.cache.data, bytes, 0, len(data))
	_, first_poll_err := fixture.cache.poll(fixture.cache.data)
	_, second_poll_err := fixture.cache.poll(fixture.cache.data)
	write_requests: [2]int
	write_count := 0
	for request, i in fixture.fake.requests[:fixture.fake.request_count] {
		if request.user_data.op == .WRITE && write_count < len(write_requests) {
			write_requests[write_count] = i
			write_count += 1
		}
	}
	if write_count == 2 {
		cache_test_io_complete(&fixture.fake, write_requests[1], 8192)
	}

	// Act
	_, later_completion_err := fixture.cache.poll(fixture.cache.data)
	persisted_after_later := fixture.persisted
	first_write := cache_test_io_find(&fixture.fake, .WRITE)
	if first_write >= 0 {
		cache_test_io_complete(&fixture.fake, first_write, 8192)
	}
	_, first_completion_err := fixture.cache.poll(fixture.cache.data)

	// Assert
	testing.expect_value(t, write_err, rifle.RifleError.None)
	testing.expect_value(t, first_poll_err, rifle.RifleError.None)
	testing.expect_value(t, second_poll_err, rifle.RifleError.None)
	testing.expect_value(t, write_count, 2)
	testing.expect_value(t, later_completion_err, rifle.RifleError.None)
	testing.expect_value(t, persisted_after_later, i64(0))
	testing.expect(t, first_write >= 0)
	testing.expect_value(t, first_completion_err, rifle.RifleError.None)
	testing.expect_value(t, fixture.persisted, i64(2048))
}

@(test)
given_failed_file_unlink_when_polled_again_then_same_file_is_retried :: proc(t: ^testing.T) {
	// Arrange
	fixture := cache_test_setup(t)
	fixture.dropped = 1024
	_, queue_err := fixture.cache.poll(fixture.cache.data)
	delete_request := cache_test_io_find(&fixture.fake, .DELETE)
	first_file := delete_request >= 0 ? fixture.fake.requests[delete_request].file_id : -1
	if delete_request >= 0 {
		cache_test_io_complete(&fixture.fake, delete_request, -i32(linux.Errno.EIO))
	}
	_, failure_err := fixture.cache.poll(fixture.cache.data)

	// Act
	_, retry_err := fixture.cache.poll(fixture.cache.data)
	retry_request := cache_test_io_find(&fixture.fake, .DELETE)
	retry_file := retry_request >= 0 ? fixture.fake.requests[retry_request].file_id : -1

	// Assert
	testing.expect_value(t, queue_err, rifle.RifleError.None)
	testing.expect(t, delete_request >= 0)
	testing.expect_value(t, failure_err, rifle.RifleError.FileOperationError)
	testing.expect_value(t, retry_err, rifle.RifleError.None)
	testing.expect(t, retry_request >= 0)
	testing.expect_value(t, first_file, i64(0))
	testing.expect_value(t, retry_file, first_file)
}

@(test)
given_partial_page_of_visible_records_when_sync_is_requested_then_data_write_is_queued_before_sync :: proc(t: ^testing.T) {
	// Arrange
	fixture := cache_test_setup(t)
	data := [1]i64{41}
	bytes := (cast([^]u8)raw_data(data[:]))[:size_of(data)]
	write_err := fixture.cache.write(fixture.cache.data, bytes, 0, 1)
	fixture.cache.sync(fixture.cache.data)

	// Act
	_, poll_err := fixture.cache.poll(fixture.cache.data)
	write_request := cache_test_io_find(&fixture.fake, .WRITE)

	// Assert
	testing.expect_value(t, write_err, rifle.RifleError.None)
	testing.expect_value(t, poll_err, rifle.RifleError.None)
	testing.expect(t, write_request >= 0)
}

@(test)
given_larger_record_cache_capacities_when_arena_size_is_calculated_then_required_space_increases :: proc(t: ^testing.T) {
	// Arrange
	ring_size := CACHE_TEST_RING_SIZE
	cache_size := CACHE_TEST_PAGE_CAPACITY
	page_size := CACHE_TEST_PAGE_SIZE
	commit_size := CACHE_TEST_COMMIT_RING_SIZE

	// Act
	base := rifle.record_cache_arena_size(ring_size, cache_size, page_size, commit_size)
	larger_ring := rifle.record_cache_arena_size(ring_size * 2, cache_size, page_size, commit_size)
	larger_cache := rifle.record_cache_arena_size(ring_size, cache_size * 2, page_size, commit_size)
	larger_commit := rifle.record_cache_arena_size(ring_size, cache_size, page_size, commit_size * 2)

	// Assert
	testing.expect(t, base > 0)
	testing.expect(t, larger_ring > base)
	testing.expect(t, larger_cache > base)
	testing.expect(t, larger_commit > base)
}
