package rifle

import "core:mem"
import "core:os"
import "core:strings"

FILE_EXTENSION :: ".rfl"
BASE_FILENAME :: "base.rfl"
DATA_PREFIX :: "data_"
PATH_SEPARATOR :: "/"

BASE_VERSION :: u32(1)

BaseFileContent :: struct {
	magic:   [4]u8,
	version: u32,
	data:    BaseFileData,
}

BaseFileData :: struct {
	record_size: i64,
	file_size:   i64,
	head:        i64,
	tail:        i64,
	schema:      RecordSchema,
}

// On-disk header-file format. Little-endian.
// - magic 4xu8
// - version u32
// - record_size i64
// - file_size i64
// - head i64
// - tail i64
// - num_schema_fields i64
// - List of SchemaFields
//   - name_length i64
//   - name chars
//	 - type FieldType
//	 - offset i64
//	 - field_size i64

// Bytes before the schema
BASE_FILE_PREFIX_SIZE :: 4 + 4 + 8 + 8 + 8 + 8

base_file_encode :: proc(data: BaseFileData, allocator := context.allocator) -> ([]u8, RifleError) {
	if len(data.schema.fields) == 0 ||
	   data.record_size <= 0 ||
	   data.file_size <= 0 ||
	   data.tail < 0 ||
	   data.head < data.tail ||
	   data.schema.record_size != data.record_size {
		return nil, .InvalidArgError
	}
	schema_bytes, schema_err := schema_encode(data.schema, allocator)
	if schema_err != .None {
		return nil, schema_err == .AllocatorError ? .AllocatorError : .InvalidArgError
	}
	defer delete(schema_bytes, allocator)
	bytes, alloc_err := make([]u8, BASE_FILE_PREFIX_SIZE + len(schema_bytes), allocator)
	if alloc_err != nil {
		return nil, .AllocatorError
	}
	copy(bytes[:4], "RFLE")
	w := 4
	put(bytes, &w, u32le(BASE_VERSION))
	put(bytes, &w, i64le(data.record_size))
	put(bytes, &w, i64le(data.file_size))
	put(bytes, &w, i64le(data.head))
	put(bytes, &w, i64le(data.tail))
	copy(bytes[w:], schema_bytes)
	return bytes, nil
}

base_file_decode :: proc(bytes: []u8, allocator := context.allocator) -> (BaseFileData, RifleError) {
	if len(bytes) < BASE_FILE_PREFIX_SIZE + SCHEMA_PREAMBLE_SIZE || string(bytes[:4]) != "RFLE" {
		return {}, .InvalidFileFormatError
	}
	r := 4
	if u32(get(bytes, &r, u32le)) != BASE_VERSION {
		return {}, .InvalidFileFormatError
	}
	data: BaseFileData
	data.record_size = i64(get(bytes, &r, i64le))
	data.file_size = i64(get(bytes, &r, i64le))
	data.head = i64(get(bytes, &r, i64le))
	data.tail = i64(get(bytes, &r, i64le))
	if data.record_size <= 0 || data.file_size <= 0 || data.tail < 0 || data.head < data.tail {
		return {}, .InvalidFileFormatError
	}
	schema, schema_err := schema_decode(bytes[r:], data.record_size, allocator)
	if schema_err != .None {
		return {}, schema_err == .AllocatorError ? .AllocatorError : .InvalidFileFormatError
	}
	expected_size := BASE_FILE_PREFIX_SIZE + SCHEMA_PREAMBLE_SIZE
	for field in schema.fields {
		expected_size += SCHEMA_FIELD_SIZE + len(field.name)
	}
	if len(bytes) != expected_size {
		schema_destroy(schema, allocator)
		return {}, .InvalidFileFormatError
	}
	data.schema = schema
	return data, nil
}

create_base_file :: proc(l: ^Log) -> RifleError {
	schema := l.config.schema
	bytes := base_file_encode({record_size = schema.record_size, file_size = l.config.file_size_bytes, schema = schema}) or_return
	defer delete(bytes)
	path := strings.concatenate({string(l.config.log_path), PATH_SEPARATOR, BASE_FILENAME})
	defer delete(path)
	file, err := os.create(path)
	if err != nil {
		return .FileOperationError
	}
	defer os.close(file)
	written, write_err := os.write(file, bytes)
	if write_err != nil || written != len(bytes) {
		return .FileOperationError
	}
	return nil
}

read_base_file :: proc(path: cstring, allocator := context.allocator) -> (BaseFileData, RifleError) {
	bytes, err := os.read_entire_file(string(path), allocator)
	if err != nil {
		return {}, .FileOperationError
	}
	defer delete(bytes, allocator)
	return base_file_decode(bytes, allocator)
}

get :: proc(bytes: []u8, r: ^int, $T: typeid) -> T {
	v: T
	copy(mem.ptr_to_bytes(&v), bytes[r^:][:size_of(T)])
	r^ += size_of(T)
	return v
}

put :: proc(bytes: []u8, w: ^int, value: $T) {
	v := value
	copy(bytes[w^:], mem.ptr_to_bytes(&v))
	w^ += size_of(T)
}
