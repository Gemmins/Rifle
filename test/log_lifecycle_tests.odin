package test

import "core:os"
import "core:strings"
import "core:testing"
import "core:time"
import rifle "rifle:rifle"

Lifecycle_Files :: struct {
	directory: string,
	path:      cstring,
	base:      string,
	base_path: cstring,
}

lifecycle_files :: proc(t: ^testing.T) -> Lifecycle_Files {
	testing.set_fail_timeout(t, 10 * time.Second)
	files := new(Lifecycle_Files)
	testing.cleanup(t, proc(ctx: rawptr) {
			files := cast(^Lifecycle_Files)ctx
			if len(files.directory) != 0 {os.remove_all(files.directory)}
			delete(files.base_path)
			delete(files.base)
			delete(files.path)
			delete(files.directory)
			free(files)
		}, files)
	directory, err := os.make_directory_temp("", "rifle-lifecycle-*", context.allocator)
	if !testing.expect(t, err == nil) {testing.fail_now(t)}
	files.directory = directory
	files.path = strings.clone_to_cstring(directory)
	files.base = strings.concatenate({directory, "/", rifle.BASE_FILENAME})
	files.base_path = strings.clone_to_cstring(files.base)
	return files^
}

lifecycle_config :: proc(path: cstring, schema: rifle.RecordSchema) -> rifle.LogConfig {
	config := rifle.DefaultLogConfig
	config.log_path = path
	config.schema = schema
	config.page_size_bytes = 4096
	config.cache_size_bytes = 4 * 4096
	config.file_size_bytes = 2 * 4096
	config.commit_ring_size = 8
	config.max_open_files = 4
	return config
}

@(test)
log_lifecycle_create_close_delete :: proc(t: ^testing.T) {
	files := lifecycle_files(t)
	schema, _, schema_err := rifle.schema_create(16, []rifle.FieldDesc{{name = "sequence", type = .U64}, {name = "value", type = .F64, offset = 8}})
	if !testing.expect(t, schema_err == .None) {return}
	defer rifle.schema_destroy(schema)
	config := lifecycle_config(files.path, schema)
	log, err := rifle.log_init(config, nil)
	if !testing.expect(t, err == nil && log != nil) {return}
	defer if log != nil {rifle.log_deinit(log)}

	header, read_err := rifle.read_base_file(files.base_path)
	if !testing.expect(t, read_err == nil) {return}
	defer rifle.schema_destroy(header.schema)
	testing.expect(t, header.record_size == 16 && header.file_size == config.file_size_bytes)
	testing.expect(t, header.head == 0 && header.tail == 0)
	if testing.expect(t, len(header.schema.fields) == len(schema.fields)) {
		for field, i in header.schema.fields {testing.expect(t, field == schema.fields[i])}
	}
	close_err := rifle.log_deinit(log)
	log = nil
	if !testing.expect(t, close_err == nil) {return}
	// Closing releases resources but preserves the persisted log.
	testing.expect(t, os.exists(files.base))
	// There is no log-delete API: delete the closed log's directory explicitly.
	testing.expect(t, os.remove_all(files.directory) == nil)
	testing.expect(t, !os.exists(files.directory))
	_, deleted_err := rifle.read_base_file(files.base_path)
	testing.expect(t, deleted_err == .FileOperationError)
}

@(test)
log_lifecycle_reopen_from_file :: proc(t: ^testing.T) {
	files := lifecycle_files(t)
	fields := []rifle.SchemaField{{name = "sequence", type = .U64, size = 8}, {name = "value", type = .F64, offset = 8, size = 8}}
	// Persist a nonempty logical range to catch accidental startup resets.
	// No data reads are attempted: this test exercises header restoration.
	original := rifle.BaseFileData {
		record_size = 16,
		file_size = 8192,
		head = 12,
		tail = 4,
		schema = {record_size = 16, fields = fields},
	}
	bytes, encode_err := rifle.base_file_encode(original)
	if !testing.expect(t, encode_err == nil) {return}
	defer delete(bytes)
	if !testing.expect(t, os.write_entire_file(files.base, bytes) == nil) {return}

	// Schema and file size must come from the file, not caller defaults.
	config := lifecycle_config(files.path, {})
	config.file_size_bytes = 4096
	log, err := rifle.log_init(config, files.base_path)
	if !testing.expect(t, err == nil && log != nil) {return}
	defer if log != nil {rifle.log_deinit(log)}
	testing.expect(t, log.config.schema.record_size == 16)
	testing.expect(t, log.config.file_size_bytes == 8192)
	if testing.expect(t, len(log.config.schema.fields) == len(fields)) {
		for field, i in log.config.schema.fields {testing.expect(t, field == fields[i])}
	}
	testing.expect(t, log.commited_index.value == 12)
	testing.expect(t, log.visible_index.value == 12)
	testing.expect(t, log.durable_index.value == 12)
	testing.expect(t, log.trailing_index.value == 4)
	close_err := rifle.log_deinit(log)
	log = nil
	testing.expect(t, close_err == nil)
	// Reopening/closing without writes must not truncate or reset the header.
	after, read_err := os.read_entire_file(files.base, context.allocator)
	defer delete(after)
	testing.expect(t, read_err == nil)
	testing.expect(t, string(after) == string(bytes))
}

@(test)
log_lifecycle_reopen_missing_file :: proc(t: ^testing.T) {
	files := lifecycle_files(t)
	log, err := rifle.log_init(lifecycle_config(files.path, {}), files.base_path)
	defer if log != nil {rifle.log_deinit(log)}
	testing.expect(t, log == nil)
	testing.expect(t, err == .FileOperationError)
	testing.expect(t, !os.exists(files.base))
}

@(test)
log_lifecycle_reopen_corrupt_file :: proc(t: ^testing.T) {
	files := lifecycle_files(t)
	corrupt := []u8{'R', 'F', 'L', 'E', 1}
	if !testing.expect(t, os.write_entire_file(files.base, corrupt) == nil) {return}
	log, err := rifle.log_init(lifecycle_config(files.path, {}), files.base_path)
	defer if log != nil {rifle.log_deinit(log)}
	testing.expect(t, log == nil)
	testing.expect(t, err == .InvalidFileFormatError)
	after, read_err := os.read_entire_file(files.base, context.allocator)
	defer delete(after)
	testing.expect(t, read_err == nil)
	testing.expect(t, string(after) == string(corrupt))
}
