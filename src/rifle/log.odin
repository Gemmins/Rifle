package rifle

import "core:mem/virtual"
import "core:sync"
import "core:sys/linux"
import "core:sys/linux/uring"

// TODO: shutdown + restart from file

// Don't copy after init :)
Log :: struct {
	arena:          virtual.Arena,
	config:         LogConfig,
	record_size:    i64,
	dirfd:          linux.Fd,
	cache:          Cache,
	io:             IO,
	commit_mask:    u64,
	commit_ring:    []paddedValue(i64),
	commited_index: paddedValue(i64),
	visible_index:  paddedValue(i64),
	durable_index:  paddedValue(i64),
	trailing_index: paddedValue(i64),
}

LogConfig :: struct {
	log_path:         cstring, // Directory that will hold all log files
	cache_size_bytes: i64, // Power of 2
	file_size_bytes:  i64, // Log will only delete whole files at a time
	page_size_bytes:  i64, // Power of 2 >= 4K
	max_open_files:   u16, // <= 4K
	commit_ring_size: i64, // Power of 2 (make reasonable size)
}

// TODO: These are just resonable guesses of numbers atm - refine later
DefaultLogConfig :: LogConfig{nil, 1 << 26, 1 << 32, 1 << 13, 1 << 8, 1 << 8}


__log_init :: proc(log: ^Log, config: LogConfig) -> (^Log, RifleError) {
	log.cache.init(
		log.cache.data,
		log.config.cache_size_bytes,
		log.config.page_size_bytes,
		log.io,
		cast(string)log.config.log_path,
		log.config.file_size_bytes,
		&log.durable_index.value,
	)

	log.commit_ring, _ = make([]paddedValue(i64), log.config.commit_ring_size)
	for &v in log.commit_ring {
		sync.atomic_store(&v.value, -1)
	}
	log.commit_mask = cast(u64)log.config.commit_ring_size - 1

	return log, nil
}

// Initialise the log - do not copy Log struct
log_init :: proc(config: LogConfig, log_file: cstring) -> (^Log, RifleError) {
	if log_file != nil {
		// Load & initialise from file
		return nil, .UnimplementedError
	}

	if config.log_path == nil {
		return nil, .InvalidArgError
	}
	arena_size := config.cache_size_bytes + (1 << 16) // TODO: actually figure this out
	log, error := virtual.arena_growing_bootstrap_new(Log, "arena", cast(uint)arena_size)
	if error != nil {
		return nil, .AllocatorError
	}
	context.allocator = virtual.arena_allocator(&log.arena)

	dirfd, err := linux.open(log.config.log_path, {.DIRECTORY, .PATH}, {})
	if err != nil {
		return nil, .FileOperationError
	}
	log.dirfd = dirfd

	#partial switch ODIN_OS {
	case .Linux:
		// TODO: actually configure these ring params
		config := UringConfig{uring.DEFAULT_PARAMS, log.config.max_open_files, cast(u64)log.config.file_size_bytes}
		log.io = new_uring_io(config, log.dirfd)
	case:
		return nil, .UnsupportedPlatformError
	}

	log.cache = new_page_cache()
	return __log_init(log, config)
}

// Free all resources held by the log
log_deinit :: proc(log: ^Log) -> RifleError {
	log.io.deinit(log.io.data)
	log.cache.deinit(log.cache.data)

	err := linux.close(log.dirfd)
	if err != nil {
		return .FileOperationError
	}

	virtual.arena_destroy(&log.arena)
	return nil
}

// Read __count_ records from _index_ to _index + count_ into _buf_
log_read :: proc(log: ^Log, buf: []u8, index: i64, count: i64) -> RifleError {
	if index + count > sync.atomic_load(&log.visible_index.value) || index < sync.atomic_load(&log.trailing_index.value) { 	// >= ?
		return .IndexOutOfBoundsError
	}
	log.cache.read(log.cache.data, buf, index, count)
	return nil
}

// Write _count_ records from _data_ into the log
log_write :: proc(log: ^Log, data: []u8, count: i64) -> (i64, RifleError) {
	index := sync.atomic_add(&log.commited_index.value, count)
	log.cache.write(log.cache.data, data, index, count)
	// Update commit ring here and try update visible index
	return 0, nil
}

// Delete records with index < _index_
log_drop :: proc(log: ^Log, index: i64) -> RifleError {
	if index > sync.atomic_load(&log.visible_index.value) {
		return .IndexOutOfBoundsError
	}
	for trailing_index := sync.atomic_load(&log.trailing_index.value); trailing_index < index; {
		if _, ok := sync.atomic_compare_exchange_strong(&log.trailing_index.value, trailing_index, index); ok {
			log.cache.drop(log.cache.data, index)
			return nil
		}
	}
	return .IndexOutOfBoundsError
}

// Progress the log state
log_poll :: proc(log: ^Log) -> (bool, RifleError) {
	return log.cache.poll(&log.cache.data)
}

// Shold this block? If so should it poll? If not then do we bother returning anything?
// Signal the log to sync all currently visible records to disk
log_sync :: proc(log: ^Log) -> i64 {
	sync_index := sync.atomic_load(&log.visible_index.value)
	// Check if someone submitted higher index?
	// Maybe make cache return its sync index (make cache only set sync index if higher)
	log.cache.sync(&log.cache.data, sync_index)
	return sync_index
}
