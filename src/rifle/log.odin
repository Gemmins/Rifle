package rifle

import "core:mem/virtual"
import "core:sync"

// Don't copy after init :)
Log :: struct {
	arena:          virtual.Arena,
	config:         LogConfig,
	path_slice:     []u8,
	record_size:    i64,
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
	log_path:         cstring,
	cache_size_bytes: i64,
	file_size_bytes:  i64,
	page_size_bytes:  i64,
}

DefaultLogConfig :: LogConfig{nil, 1 << 26, 1 << 32, 1 << 13}

@(private)
log_init_private :: proc(log: ^Log, config: LogConfig) -> (^Log, RifleError) {
	log.cache.init(
		log.cache.data,
		log.config.cache_size_bytes,
		log.config.page_size_bytes,
		log.io,
		cast(string)log.config.log_path, // Type?
		log.config.file_size_bytes,
		&log.durable_index.value,
	)
	return log, nil
}

log_init :: proc(config: LogConfig) -> (^Log, RifleError) {
	if config.log_path == nil {
		return nil, .InvalidArgError
	}
	arena_size := config.cache_size_bytes + 1 << 16 // TODO: actually figure this out
	log, error := virtual.arena_growing_bootstrap_new(Log, "arena", cast(uint)arena_size)
	if error != nil {
		return nil, .AllocatorError
	}
	context.allocator = virtual.arena_allocator(&log.arena)

	// Large compile time switch here to determine io impl?
	log.io = new_uring_io({}, 0)
	log.cache = new_page_cache()

	return log_init_private(log, config)
}

log_deinit :: proc(log: ^Log) -> RifleError {
	log.io.deinit(log.io.data)
	log.cache.deinit(log.cache.data)
	virtual.arena_destroy(&log.arena)
	return nil
}

log_read :: proc(log: ^Log, buf: []u8, index: i64, count: i64) -> RifleError {
	if index + count > sync.atomic_load(&log.visible_index.value) { 	// >= ?
		return .IndexOutOfBoundsError
	}
	log.cache.read(log.cache.data, buf, index, count)
	return nil
}

log_write :: proc(log: ^Log, data: []u8, count: i64) -> (i64, RifleError) {
	index := sync.atomic_add(&log.commited_index.value, count)
	log.cache.write(log.cache.data, data, index, count)
	// Update commit ring here and try update visible index
	return 0, nil
}

log_poll :: proc(log: ^Log) -> (bool, RifleError) {
	return log.cache.poll(&log.cache.data)
}

// Shold this block? If so should it poll? If not then do we bother returning anythign
log_sync :: proc(log: ^Log) -> i64 {
	sync_index := sync.atomic_load(&log.visible_index.value)
	// Check if someone submitted higher index?
	// Maybe make cache return its sync index (make cache only set sync index if higher)
	log.cache.sync(&log.cache.data, sync_index)
	return sync_index
}
