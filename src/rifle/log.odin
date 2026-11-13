package rifle

import "base:runtime"
import "core:math/bits"
import "core:strings"
import "core:sync"
import "core:sys/linux"
import "core:sys/linux/uring"

// Don't copy after init :)
Log :: struct {
	allocator:       runtime.Allocator,
	arena:           ^FileBackedArena,
	config:          LogConfig,
	dirfd:           linux.Fd,
	cache:           Cache,
	io:              IO,
	memfd:           linux.Fd,
	commited_index:  paddedValue(i64),
	visible_index:   paddedValue(i64),
	persisted_index: paddedValue(i64),
	durable_index:   paddedValue(i64),
	trailing_index:  paddedValue(i64),
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


__log_init :: proc(log: ^Log) -> (err: RifleError) {
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

// Initialise the log - do not copy Log struct
log_init :: proc(config: LogConfig, log_file: cstring) -> (^Log, RifleError) {

	// TODO: maybe don't want to hard error on file, cache size issue but just round to nearest pssible value
	// Maybe move these
	if log_file == nil && (config.log_path == nil || len(config.log_path) == 0 || config.schema.record_size <= 0 || len(config.schema.fields) == 0) {
		return nil, .InvalidArgError
	}
	if config.page_size_bytes < 4096 || config.page_size_bytes > i64(max(i32)) || bits.count_ones(config.page_size_bytes) != 1 {
		return nil, .InvalidArgError
	}
	if config.ring_size_bytes < config.page_size_bytes || config.ring_size_bytes > 1 << 36 || bits.count_ones(config.ring_size_bytes) != 1 {
		return nil, .InvalidArgError
	}
	if log_file == nil && config.schema.record_size > config.ring_size_bytes {
		return nil, .InvalidArgError
	}
	if config.page_cache_size_bytes <= 0 || bits.count_ones(config.page_cache_size_bytes) != 1 || config.page_cache_size_bytes % config.page_size_bytes != 0 {
		return nil, .InvalidArgError
	}
	num_pages := config.page_cache_size_bytes / config.page_size_bytes
	if num_pages < SET_ASSOC || num_pages % SET_ASSOC != 0 || num_pages > 1 << 24 {
		return nil, .InvalidArgError
	}
	if config.read_chunk_size < 0 || config.read_chunk_size > num_pages / SET_ASSOC {
		return nil, .InvalidArgError
	}
	if config.file_size_bytes <= 0 || config.file_size_bytes % config.page_size_bytes != 0 || config.max_open_files == 0 || config.max_open_files > 1 << 12 {
		return nil, .InvalidArgError
	}
	if config.commit_ring_size <= 0 || bits.count_ones(config.commit_ring_size) != 1 || config.commit_ring_size > i64(max(int) / size_of(paddedValue(i64))) {
		return nil, .InvalidArgError
	}

	// TODO: bootstrap Log inside the file-backed arena.
	allocator := context.allocator
	log, error := new(Log, allocator)
	if error != nil {
		return nil, .AllocatorError
	}
	log.allocator = allocator
	success := false
	defer if !success {
		free(log, allocator)
	}
	memfd, errno := linux.memfd_create("something", {.CLOEXEC}) // TODO: name
	if errno != .NONE {
		return nil, .GenericError
	}
	defer if !success {
		linux.close(memfd)
	}
	log.memfd = memfd
	arena_size :=
		2 * config.ring_size_bytes +
		config.page_cache_size_bytes +
		num_pages * size_of(RecordCachePage) +
		num_pages / SET_ASSOC * size_of(RecordCacheSet(SET_ASSOC)) +
		config.commit_ring_size * size_of(paddedValue(i64)) +
		(1 << 24)
	arena_size = (arena_size + config.page_size_bytes - 1) & ~(config.page_size_bytes - 1)
	arena, arena_err := new_file_backed_arena(memfd, arena_size)
	if arena_err != nil {
		return nil, arena_err
	}
	log.arena = cast(^FileBackedArena)arena.data
	defer if !success {
		destroy_file_backed_arena(log.arena)
	}
	context.allocator = arena

	log.config = config

	// For now use this path even if load from file but maybe swap at some point
	path, path_err := strings.clone_to_cstring(cast(string)config.log_path)
	if path_err != nil {
		return nil, .AllocatorError
	}
	log.config.log_path = path

	dirfd, err := linux.open(log.config.log_path, {.DIRECTORY, .PATH}, {})
	if err != nil {
		return nil, .FileOperationError
	}
	defer {
		if !success {
			linux.close(dirfd)
		}
	}
	log.dirfd = dirfd

	if log_file != nil {
		log_metadata, err := read_base_file(log_file)
		if err != nil {
			return nil, err
		}
		log.config.file_size_bytes = log_metadata.file_size
		log.config.schema = log_metadata.schema
		if log.config.schema.record_size > config.ring_size_bytes || log.config.file_size_bytes % config.page_size_bytes != 0 {
			return nil, .InvalidArgError
		}
		log.durable_index.value = log_metadata.head
		log.trailing_index.value = log_metadata.tail
		log.persisted_index.value = log.durable_index.value
		log.visible_index.value = log.durable_index.value
		log.commited_index.value = log.durable_index.value
	} else {
		file_err := create_base_file(log)
		if file_err != nil {
			return nil, file_err
		}
	}

	#partial switch ODIN_OS {
	case .Linux:
		// TODO: actually configure these ring params
		config := UringConfig{uring.DEFAULT_PARAMS, log.config.max_open_files, cast(u64)log.config.file_size_bytes}
		log.io = new_uring_io(config, log.dirfd)
	case:
		return nil, .UnsupportedPlatformError
	}

	log.cache = new_record_cache()
	init_err := __log_init(log)
	if init_err != nil {
		return nil, init_err
	}

	success = true
	return log, nil
}

// Free all resources held by the log
log_deinit :: proc(log: ^Log) -> RifleError {
	defer free(log, log.allocator)
	context.allocator = {file_backed_arena_proc, log.arena}
	cache_err := log.cache.deinit(log.cache.data)

	dir_err := linux.close(log.dirfd)
	mem_err := linux.close(log.memfd)
	arena_err := destroy_file_backed_arena(log.arena)
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
	if count > i64(len(buf)) / log.config.schema.record_size {
		return .BufferTooSmallError
	}
	return log.cache.read(log.cache.data, buf, index, count)
}

// Write _count_ records from _data_ into the log
log_write :: proc(log: ^Log, data: []u8, count: i64) -> (index: i64, err: RifleError) {
	if count < 0 {
		return 0, .InvalidArgError
	}
	if count > i64(len(data)) / log.config.schema.record_size {
		return 0, .BufferTooSmallError
	}
	index = sync.atomic_add(&log.commited_index.value, count)
	log.cache.write(log.cache.data, data, index, count) or_return

	return index, nil
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
