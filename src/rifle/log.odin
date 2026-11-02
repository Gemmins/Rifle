package rifle

import "base:runtime"
import "core:math/bits"
import "core:mem/virtual"
import "core:strings"
import "core:sync"
import "core:sys/linux"
import "core:sys/linux/uring"

// TODO: shutdown + restart from file

// Don't copy after init :)
Log :: struct {
	arena:          virtual.Arena,
	config:         LogConfig,
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
	schema:           RecordSchema, // Required; caller keeps fields/names alive until log_deinit
}

// TODO: Choose properly
DefaultLogConfig :: LogConfig{nil, 1 << 26, 1 << 32, 1 << 13, 1 << 8, 1 << 8, {}}


__log_init :: proc(log: ^Log) -> (err: RifleError) {
	log.cache.init(
		log.cache.data,
		log.config.cache_size_bytes,
		log.config.page_size_bytes,
		log.io,
		cast(string)log.config.log_path,
		log.config.file_size_bytes,
		log.config.schema.record_size,
		&log.durable_index.value,
	) or_return

	error: runtime.Allocator_Error
	log.commit_ring, error = make([]paddedValue(i64), log.config.commit_ring_size)
	if error != nil {
		return .AllocatorError
	}

	for &v in log.commit_ring {
		sync.atomic_store(&v.value, -1)
	}
	log.commit_mask = cast(u64)log.config.commit_ring_size - 1

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
	if config.cache_size_bytes <= 0 || bits.count_ones(config.cache_size_bytes) != 1 || config.cache_size_bytes % config.page_size_bytes != 0 {
		return nil, .InvalidArgError
	}
	num_pages := config.cache_size_bytes / config.page_size_bytes
	if num_pages < SET_ASSOC || num_pages % SET_ASSOC != 0 || num_pages > 1 << 24 {
		return nil, .InvalidArgError
	}
	if config.file_size_bytes <= 0 || config.file_size_bytes % config.page_size_bytes != 0 || config.max_open_files == 0 || config.max_open_files > 1 << 12 {
		return nil, .InvalidArgError
	}
	if config.commit_ring_size <= 0 || bits.count_ones(config.commit_ring_size) != 1 || config.commit_ring_size > i64(max(int) / size_of(paddedValue(i64))) {
		return nil, .InvalidArgError
	}

	arena_size := config.cache_size_bytes + (1 << 16) // TODO: actually figure this out
	log, error := virtual.arena_growing_bootstrap_new(Log, "arena", cast(uint)arena_size)
	if error != nil {
		return nil, .AllocatorError
	}
	success := false
	defer {
		if !success {
			arena := log.arena
			virtual.arena_destroy(&arena)
		}
	}
	context.allocator = virtual.arena_allocator(&log.arena)

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
		log.durable_index.value = log_metadata.head
		log.trailing_index.value = log_metadata.tail
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

	log.cache = new_page_cache()
	init_err := __log_init(log)
	if init_err != nil {
		return nil, init_err
	}

	success = true
	return log, nil
}

// Free all resources held by the log
log_deinit :: proc(log: ^Log) -> RifleError {
	context.allocator = virtual.arena_allocator(&log.arena)
	log.cache.deinit(log.cache.data)

	err := linux.close(log.dirfd)
	if err != nil {
		return .FileOperationError
	}

	arena := log.arena
	virtual.arena_destroy(&arena)
	return nil
}

// Read _count_ records from _index_ to _index + count_ into _buf_
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

	next := index
	to_commit := count
	// TODO: This will spin if a slow write from someone else (large batch) so we might want some
	// gradual fallback to using cpu_relax() or somthing else at some point.
	for to_commit > 0 {
		visible := sync.atomic_load(&log.visible_index.value)
		available := max(i64(0), i64(len(log.commit_ring)) - (next - visible))
		c := min(to_commit, available)
		end := next + c
		for ; next < end; next += 1 {
			sync.atomic_store(&log.commit_ring[cast(u64)next & log.commit_mask].value, next)
		}
		to_commit -= c

		for {
			head := sync.atomic_load(&log.visible_index.value)
			if sync.atomic_load(&log.commit_ring[cast(u64)head & log.commit_mask].value) != head {
				break
			}
			sync.atomic_compare_exchange_strong(&log.visible_index.value, head, head + 1)
		}
	}
	return index, nil
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
