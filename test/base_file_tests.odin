package test

import "core:os"
import "core:strings"
import "core:testing"
import rifle "rifle:rifle"

@(test)
base_file_roundtrip_and_validation :: proc(t: ^testing.T) {
	fields := []rifle.SchemaField{{name = "value", type = .U64, size = 8}}
	original := rifle.BaseFileData {
		record_size = 8,
		file_size = 4096,
		head = 17,
		tail = 3,
		schema = {record_size = 8, fields = fields},
	}
	bytes, err := rifle.base_file_encode(original)
	if !testing.expect(t, err == nil) {return}
	defer delete(bytes)
	testing.expect(t, len(bytes) == 40 + 16 + 25 + 5)
	testing.expect(t, string(bytes[:4]) == "RFLE")
	// Literal bytes verify endianness independently of the host and codec.
	expected := []u8 {
		'R',
		'F',
		'L',
		'E',
		1,
		0,
		0,
		0,
		8,
		0,
		0,
		0,
		0,
		0,
		0,
		0, // record size
		0,
		16,
		0,
		0,
		0,
		0,
		0,
		0, // file size: 4096
		17,
		0,
		0,
		0,
		0,
		0,
		0,
		0, // head
		3,
		0,
		0,
		0,
		0,
		0,
		0,
		0, // tail
		8,
		0,
		0,
		0,
		0,
		0,
		0,
		0, // schema record size
		1,
		0,
		0,
		0,
		0,
		0,
		0,
		0, // field count
		5,
		0,
		0,
		0,
		0,
		0,
		0,
		0, // name length
		'v',
		'a',
		'l',
		'u',
		'e',
		13, // name, U64
		0,
		0,
		0,
		0,
		0,
		0,
		0,
		0, // offset
		8,
		0,
		0,
		0,
		0,
		0,
		0,
		0, // field size
	}
	testing.expect(t, string(bytes) == string(expected))
	decoded, decode_err := rifle.base_file_decode(expected)
	if !testing.expect(t, decode_err == nil) {return}
	defer rifle.schema_destroy(decoded.schema)
	testing.expect(t, decoded.record_size == 8 && decoded.file_size == 4096)
	testing.expect(t, decoded.head == 17 && decoded.tail == 3)
	testing.expect(t, decoded.schema.fields[0] == fields[0])
	for end in 0 ..< len(bytes) {
		_, truncated_err := rifle.base_file_decode(bytes[:end])
		testing.expect(t, truncated_err == .InvalidFileFormatError)
	}
	// Each corruption starts from the valid buffer and is then restored.
	for offset in ([]int{0, 4, 40, 69}) {
		old := bytes[offset]
		bytes[offset] = 255
		_, corrupt_err := rifle.base_file_decode(bytes)
		testing.expect(t, corrupt_err == .InvalidFileFormatError)
		bytes[offset] = old
	}
	extra := make([]u8, len(bytes) + 1)
	defer delete(extra)
	copy(extra, bytes)
	_, trailing_err := rifle.base_file_decode(extra)
	testing.expect(t, trailing_err == .InvalidFileFormatError)
}

@(test)
base_file_disk_roundtrip :: proc(t: ^testing.T) {
	path, path_err := os.make_directory_temp("", "rifle-base-*", context.allocator)
	if !testing.expect(t, path_err == nil) {return}
	defer delete(path)
	defer os.remove_all(path)
	cpath, _ := strings.clone_to_cstring(path)
	defer delete(cpath)
	filename := strings.concatenate({path, "/base.rfl"})
	defer delete(filename)
	cfilename, _ := strings.clone_to_cstring(filename)
	defer delete(cfilename)
	schema, _, schema_err := rifle.schema_create(8, []rifle.FieldDesc{{name = "value", type = .U64}})
	if !testing.expect(t, schema_err == .None) {return}
	defer rifle.schema_destroy(schema)
	log: rifle.Log
	log.config = rifle.DefaultLogConfig
	log.config.log_path = cpath
	log.config.file_size_bytes = 4096
	log.config.schema = schema
	if !testing.expect(t, rifle.create_base_file(&log) == nil) {return}
	data, err := rifle.read_base_file(cfilename)
	if !testing.expect(t, err == nil) {return}
	defer rifle.schema_destroy(data.schema)
	testing.expect(t, data.schema.fields[0] == schema.fields[0])
	testing.expect(t, data.head == 0 && data.tail == 0)
	// Missing schemas must fail before truncating the existing file.
	log.config.schema = {}
	testing.expect(t, rifle.create_base_file(&log) == .InvalidArgError)
	log.config.schema = {
		record_size = 8,
	}
	testing.expect(t, rifle.create_base_file(&log) == .InvalidArgError)
	unchanged, unchanged_err := rifle.read_base_file(cfilename)
	testing.expect(t, unchanged_err == nil)
	defer rifle.schema_destroy(unchanged.schema)
	testing.expect(t, unchanged.record_size == 8)
}
