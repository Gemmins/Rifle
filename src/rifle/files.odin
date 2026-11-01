package rifle

import "core:container/lru"
import "core:fmt"
import "core:nbio"
import "core:os"
import "core:strings"
import "core:sys/linux"

FILE_EXTENSION :: ".rfl"
BASE_FILENAME :: "base.rfl"
DATA_PREFIX :: "data_"
PATH_SEPARATOR :: "/"

BASE_VERSION :: u32(1)

BaseHeader :: struct {
	magic:           [4]u8,
	version:         u32,
	record_size:     i64,
	page_size_bytes: i64,
	file_size_bytes: i64,
}

log_create_or_open_storage_file :: proc(l: ^Log_old, index: i64) -> (err: RifleError) {
	path := fmt.bprint(l.path_slice, l.base_path, PATH_SEPARATOR, DATA_PREFIX, index, FILE_EXTENSION, sep = "")

	nbio.open_poly2(
		path,
		l,
		index,
		register_file_handle,
		mode = {.Read, .Write, .Create, .Sync}, // TODO: think about .sync
		l = l.io_loop,
	)

	return nil
}

log_create_or_open_storage_file_blocking :: proc(l: ^Log_old, index: i64) -> (file: FileInfo, err: RifleError) {
	path := fmt.bprint(l.path_slice, l.base_path, PATH_SEPARATOR, DATA_PREFIX, index, FILE_EXTENSION, sep = "")

	handle, error := nbio.open_sync(path, mode = {.Read, .Write, .Create, .Sync}, l = l.io_loop)
	if error != nil {
		err = .FileOperationError
		fmt.println("error: %v", error)
		return
	} // TODO: handle

	fallocate_storage_file(handle, l.blocks_per_file * l.records_per_block * l.record_size) or_return

	file = FileInfo {
		handle  = handle,
		index   = index,
		readers = 0,
	}

	lru.set(l.open_files, index, file)

	return file, nil
}

register_file_handle :: proc(op: ^nbio.Operation, l: ^Log_old, index: i64) {
	handle := op.specifics.open.handle
	_ = fallocate_storage_file(handle, l.blocks_per_file * l.records_per_block * l.record_size) // TODO: handle
	lru.set(l.open_files, index, FileInfo{handle = handle, index = index, readers = 0})

}

fallocate_storage_file :: proc(handle: nbio.Handle, length: i64) -> RifleError {
	ret := linux.syscall(linux.SYS_fallocate, linux.Fd(handle), u32(0), i64(0), length)
	if ret < 0 {
		return .FileOperationError
	}
	return nil
}

ensure_base_directory_exists_or_create :: proc(path: string) -> RifleError {
	if os.exists(path) {
		if !os.is_dir(path) {
			return .InvalidArgError
		}
		return nil
	}
	if err := os.make_directory(path); err != nil {
		return .FileOperationError
	}
	return nil
}

write_base_file :: proc(l: ^Log) -> RifleError {
	path := strings.concatenate({cast(string)l.config.log_path, PATH_SEPARATOR, BASE_FILENAME})
	file, err := os.create(path)
	if err != nil {
		return .FileOperationError
	}
	defer os.close(file)

	header := BaseHeader { 	// TODO: sort this thing out
		magic           = {'R', 'F', 'L', 'E'},
		version         = BASE_VERSION,
		record_size     = l.config.record_size,
		page_size_bytes = l.config.page_size_bytes,
		file_size_bytes = l.config.file_size_bytes,
	}
	bytes := (cast([^]u8)&header)[:size_of(BaseHeader)]
	if _, write_err := os.write(file, bytes); write_err != nil {
		return .FileOperationError
	}
	return nil
}
