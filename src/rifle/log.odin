package rifle

import "core:math/bits"
import "core:strings"
import "core:sync"
import "core:sys/linux"
import "core:sys/linux/uring"
import "core:sys/posix"

// Don't copy after init :)
Log :: struct {
	commited_index:  paddedValue(i64, 128),
	visible_index:   paddedValue(i64, 128),
	persisted_index: paddedValue(i64, 128),
	durable_index:   paddedValue(i64, 128),
	trailing_index:  paddedValue(i64, 128),
	config:          LogConfig, // Read-only after initialization.
	arena:           FileBackedArena,
	dirfd:           linux.Fd,
	cache:           Cache,
	io:              IO,
	memfd:           linux.Fd,
}

LogConfig :: struct {
	log_path:              cstring, // Directory that will hold all log files
	ring_size_bytes:       i64, // Power of 2, <= 64 GiB
	page_cache_size_bytes: i64, // Power of 2
	file_size_bytes:       i64, // Log will only delete whole files at a time
	page_size_bytes:       i64, // Power of 2 >= 4K
	max_open_files:        u16, // <= 4K
	read_chunk_size:       i64, // Pages; 0 defaults to the number of sets
	commit_ring_size:      i64, // Power of 2 (make reasonable size)
	schema:                RecordSchema, // Required
}

// TODO: Choose properly
DefaultLogConfig :: LogConfig {
	ring_size_bytes       = 1 << 26,
	page_cache_size_bytes = 1 << 23,
	file_size_bytes       = 1 << 32,
	page_size_bytes       = 1 << 12,
	max_open_files        = 1 << 8,
	commit_ring_size      = 1 << 8,
}


log_init_cache :: proc(log: ^Log) -> (err: RifleError) {
	log.cache.init(
		log.cache.data,
		log.config.ring_size_bytes,
		log.config.page_cache_size_bytes,
		log.config.page_size_bytes,
		log.config.commit_ring_size,
		log.io,
		log.config.file_size_bytes,
		log.config.schema.record_size,
		&log.visible_index.value,
		&log.persisted_index.value,
		&log.durable_index.value,
		&log.trailing_index.value,
		log.config.read_chunk_size,
	) or_return

	return nil
}

log_config_validate :: proc(config: LogConfig) -> RifleError {
	if config.log_path == nil || len(config.log_path) == 0 {
		return .InvalidArgError
	}
	if config.page_size_bytes < 4096 || config.page_size_bytes > i64(max(i32)) || bits.count_ones(config.page_size_bytes) != 1 {
		return .InvalidArgError
	}
	if config.ring_size_bytes < config.page_size_bytes || config.ring_size_bytes > 1 << 36 || bits.count_ones(config.ring_size_bytes) != 1 {
		return .InvalidArgError
	}
	if config.page_cache_size_bytes <= 0 || bits.count_ones(config.page_cache_size_bytes) != 1 || config.page_cache_size_bytes % config.page_size_bytes != 0 {
		return .InvalidArgError
	}
	num_pages := config.page_cache_size_bytes / config.page_size_bytes
	if num_pages < SET_ASSOC || num_pages % SET_ASSOC != 0 || num_pages > 1 << 24 {
		return .InvalidArgError
	}
	if config.read_chunk_size < 0 || config.read_chunk_size > num_pages / SET_ASSOC {
		return .InvalidArgError
	}
	if config.file_size_bytes <= 0 || config.file_size_bytes % config.page_size_bytes != 0 || config.max_open_files == 0 || config.max_open_files > 1 << 12 {
		return .InvalidArgError
	}
	if config.commit_ring_size <= 0 ||
	   bits.count_ones(config.commit_ring_size) != 1 ||
	   config.commit_ring_size > i64(max(int) / size_of(paddedValue(i64, 128))) {
		return .InvalidArgError
	}

	_, schema_err := schema_validate(config.schema.record_size, config.schema.fields)
	if schema_err != .None || config.schema.record_size > config.ring_size_bytes {
		return .InvalidArgError
	}
	return nil
}

// Initialise the log - do not copy Log struct.
log_init :: proc(input: LogConfig, log_file: cstring) -> (^Log, RifleError) {
	config := input
	allocator := context.allocator
	metadata: BaseFileData
	if log_file != nil {
		loaded, load_err := read_base_file(log_file, allocator)
		if load_err != nil {
			return nil, load_err
		}
		metadata = loaded
		config.schema = metadata.schema
		config.file_size_bytes = metadata.file_size
	}
	defer if log_file != nil {
		schema_destroy(metadata.schema, allocator)
	}
	if err := log_config_validate(config); err != nil {
		return nil, err
	}

	arena_size := log_arena_size(config)

	success := false
	memfd, errno := linux.memfd_create("rifle-log-arena", {.CLOEXEC})
	if errno != .NONE {
		return nil, .GenericError
	}
	defer if !success {
		linux.close(memfd)
	}

	log, arena_err := file_backed_arena_bootstrap_by_name(Log, "arena", memfd, arena_size)
	if arena_err != nil {
		return nil, arena_err
	}
	defer if !success {
		destroy_file_backed_arena(&log.arena)
	}

	log.memfd = memfd
	context.allocator = {log.arena.allocator_proc, &log.arena}

	log.config = config
	schema, _, copy_err := schema_create(config.schema.record_size, config.schema.fields)
	if copy_err != .None {
		return nil, copy_err == .AllocatorError ? .AllocatorError : .InvalidArgError
	}
	log.config.schema = schema

	path, path_err := strings.clone_to_cstring(string(config.log_path))
	if path_err != nil {
		return nil, .AllocatorError
	}
	log.config.log_path = path

	log.durable_index.value = metadata.head
	log.persisted_index.value = metadata.head
	log.visible_index.value = metadata.head
	log.commited_index.value = metadata.head
	log.trailing_index.value = metadata.tail

	dirfd, err := linux.open(log.config.log_path, {.DIRECTORY, .PATH}, {})
	if err != nil {
		return nil, .FileOperationError
	}
	defer if !success {
		linux.close(dirfd)
	}
	log.dirfd = dirfd

	if log_file == nil {
		if err := create_base_file(log, allocator); err != nil {
			return nil, err
		}
	}

	#partial switch ODIN_OS {
	case .Linux:
		io_config := UringConfig{uring.DEFAULT_PARAMS, log.config.max_open_files, cast(u64)log.config.file_size_bytes}
		log.io = new_uring_io(io_config, log.dirfd)
	case:
		return nil, .UnsupportedPlatformError
	}

	log.cache = new_record_cache()
	init_err := log_init_cache(log)
	if init_err != nil {
		return nil, init_err
	}

	success = true
	return log, nil
}

// Free all resources held by the log
log_deinit :: proc(log: ^Log) -> RifleError {
	context.allocator = {log.arena.allocator_proc, &log.arena}
	cache_err := log.cache.deinit(log.cache.data)

	dir_err := linux.close(log.dirfd)
	mem_err := linux.close(log.memfd)
	arena_err := destroy_file_backed_arena(&log.arena)
	if cache_err != nil {
		return cache_err
	}
	if dir_err != nil || mem_err != nil {
		return .FileOperationError
	}
	return arena_err
}

// Read _count_ records from _index_ to _index + count_ into _buf_
log_read :: proc(log: ^Log, buf: []u8, index: i64, count: i64) -> RifleError {
	visible := sync.atomic_load(&log.visible_index.value)
	if count < 0 || index < sync.atomic_load(&log.trailing_index.value) || index > visible || count > visible - index {
		return .IndexOutOfBoundsError
	}
	return log.cache.read(log.cache.data, buf, index, count)
}

// Acquire a reference to a record range within the cache
// record range cannot cross cache page boundary
log_read_acquire :: proc(log: ^Log, index: i64, count: i64) -> ([]u8, RifleError) {
	return nil, .UnimplementedError
}

// Release a reference to a record range within the cache
log_read_release :: proc(log: ^Log, index: i64) -> RifleError {
	return .UnimplementedError
}

// Ask the log to load records from _index_ to _index + count_ into its cache
log_prefetch :: proc(log: ^Log, index: i64, count: i64) -> RifleError {
	return .UnimplementedError // TODO: implement
}

// Write _count_ records from _data_ into the log
log_write :: proc(log: ^Log, data: []u8, count: i64) -> (index: i64, err: RifleError) {
	if count < 0 {
		return 0, .InvalidArgError
	}
	index = sync.atomic_add(&log.commited_index.value, count)
	log.cache.write(log.cache.data, data, index, count) or_return

	return index, nil
}

// Acquire reference to location to write records into the log
log_write_reserve :: proc(log: ^Log, count: i64) -> (i64, []u8, RifleError) {
	return 0, nil, .UnimplementedError
}

// Signal completion of writing into the log with log_write_acquire
log_write_commit :: proc(log: ^Log, index: i64) -> RifleError {
	return .UnimplementedError
}

// Delete records with index < _index_
log_drop :: proc(log: ^Log, index: i64) -> RifleError {
	if index > sync.atomic_load(&log.visible_index.value) {
		return .IndexOutOfBoundsError
	}
	for trailing_index := sync.atomic_load(&log.trailing_index.value); trailing_index < index; {
		if _, ok := sync.atomic_compare_exchange_strong(&log.trailing_index.value, trailing_index, index); ok {
			return nil
		}
	}
	return .IndexOutOfBoundsError
}

// Progress the log state
log_poll :: proc(log: ^Log) -> (bool, RifleError) {
	return log.cache.poll(log.cache.data)
}

// Signal to the cache to persist and fsync all records
// Will be done at next poll
log_sync :: proc(log: ^Log) -> i64 {
	sync_index := sync.atomic_load(&log.visible_index.value)
	log.cache.sync(log.cache.data)
	return sync_index
}


log_arena_size :: proc(config: LogConfig) -> i64 {
	size :=
		i64(size_of(Log)) +
		i64(len(config.log_path)) +
		2 +
		schema_arena_size(config.schema) +
		record_cache_arena_size(config.ring_size_bytes, config.page_cache_size_bytes, config.page_size_bytes, config.commit_ring_size) +
		uring_io_arena_size(config.max_open_files, uring.DEFAULT_ENTRIES, 2)
	alignment := max(config.page_size_bytes, i64(posix.sysconf(._PAGE_SIZE)))
	return (size + alignment - 1) & ~(alignment - 1)
}
