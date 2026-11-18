package unit

import "base:runtime"
import "core:os"
import "core:strings"
import "core:testing"
import rifle "rifle:rifle"

@(test)
given_valid_metadata_when_encoded_then_bytes_match_documented_layout :: proc(t: ^testing.T) {
	// Arrange
	metadata := rifle.BaseFileData{
		record_size = 8,
		file_size = 4096,
		head = 17,
		tail = 3,
		schema = {record_size = 8, fields = []rifle.SchemaField{{name = "value", type = .U64, size = 8}}},
	}
	expected := [78]u8{
		'R', 'F', 'L', 'E',
		1, 0, 0, 0,
		8, 0, 0, 0, 0, 0, 0, 0,
		0, 16, 0, 0, 0, 0, 0, 0,
		17, 0, 0, 0, 0, 0, 0, 0,
		3, 0, 0, 0, 0, 0, 0, 0,
		1, 0, 0, 0, 0, 0, 0, 0,
		5, 0, 0, 0, 0, 0, 0, 0,
		'v', 'a', 'l', 'u', 'e', 13,
		0, 0, 0, 0, 0, 0, 0, 0,
		8, 0, 0, 0, 0, 0, 0, 0,
	}

	// Act
	encoded, err := rifle.base_file_encode(metadata)
	defer delete(encoded)

	// Assert
	testing.expect_value(t, err, rifle.RifleError.None)
	testing.expect_value(t, string(encoded), string(expected[:]))
}

@(test)
given_encoded_metadata_when_decoded_then_all_values_and_schema_round_trip :: proc(t: ^testing.T) {
	// Arrange
	original := rifle.BaseFileData{
		record_size = 20,
		file_size = 8192,
		head = 40,
		tail = 12,
		schema = {
			record_size = 20,
			fields = []rifle.SchemaField{
				{name = "id", type = .U64, size = 8},
				{name = "name", type = .Text, offset = 8, size = 12},
			},
		},
	}
	encoded, encode_err := rifle.base_file_encode(original)
	if !testing.expect_value(t, encode_err, rifle.RifleError.None) {
		return
	}
	defer delete(encoded)

	// Act
	decoded, decode_err := rifle.base_file_decode(encoded)
	defer rifle.schema_destroy(decoded.schema)

	// Assert
	testing.expect_value(t, decode_err, rifle.RifleError.None)
	testing.expect_value(t, decoded.record_size, original.record_size)
	testing.expect_value(t, decoded.file_size, original.file_size)
	testing.expect_value(t, decoded.head, original.head)
	testing.expect_value(t, decoded.tail, original.tail)
	testing.expect_value(t, decoded.schema.record_size, original.schema.record_size)
	for field, i in decoded.schema.fields {
		testing.expect_value(t, field, original.schema.fields[i])
	}
}

@(test)
given_invalid_metadata_when_encoded_then_invalid_argument_is_returned :: proc(t: ^testing.T) {
	// Arrange
	field := rifle.SchemaField{name = "value", type = .U64, size = 8}
	valid := rifle.BaseFileData{
		record_size = 8,
		file_size = 4096,
		schema = {record_size = 8, fields = []rifle.SchemaField{field}},
	}
	missing_schema := valid
	missing_schema.schema.fields = nil
	invalid_record_size := valid
	invalid_record_size.record_size = 0
	invalid_file_size := valid
	invalid_file_size.file_size = 0
	invalid_range := valid
	invalid_range.head = 2
	invalid_range.tail = 3
	mismatched_schema := valid
	mismatched_schema.schema.record_size = 16

	// Act
	_, missing_err := rifle.base_file_encode(missing_schema)
	_, record_err := rifle.base_file_encode(invalid_record_size)
	_, file_err := rifle.base_file_encode(invalid_file_size)
	_, range_err := rifle.base_file_encode(invalid_range)
	_, schema_err := rifle.base_file_encode(mismatched_schema)

	// Assert
	testing.expect_value(t, missing_err, rifle.RifleError.InvalidArgError)
	testing.expect_value(t, record_err, rifle.RifleError.InvalidArgError)
	testing.expect_value(t, file_err, rifle.RifleError.InvalidArgError)
	testing.expect_value(t, range_err, rifle.RifleError.InvalidArgError)
	testing.expect_value(t, schema_err, rifle.RifleError.InvalidArgError)
}

@(test)
given_truncated_corrupt_or_extended_bytes_when_decoded_then_file_format_error_is_returned :: proc(t: ^testing.T) {
	// Arrange
	valid, encode_err := rifle.base_file_encode({
		record_size = 8,
		file_size = 4096,
		head = 4,
		tail = 1,
		schema = {record_size = 8, fields = []rifle.SchemaField{{name = "value", type = .U64, size = 8}}},
	})
	if !testing.expect_value(t, encode_err, rifle.RifleError.None) {
		return
	}
	defer delete(valid)
	corruptions := [4][78]u8{}
	for &bytes in corruptions {
		copy(bytes[:], valid)
	}
	corruptions[0][0] = 'X'
	corruptions[1][4] = 2
	corruptions[2][8] = 0
	corruptions[3][61] = 0
	extended := make([]u8, len(valid) + 1)
	defer delete(extended)
	copy(extended, valid)

	// Act
	all_truncated_rejected := true
	for end in 0 ..< len(valid) {
		_, err := rifle.base_file_decode(valid[:end])
		all_truncated_rejected = all_truncated_rejected && err == .InvalidFileFormatError
	}
	all_corrupt_rejected := true
	for i in 0 ..< len(corruptions) {
		_, err := rifle.base_file_decode(corruptions[i][:])
		all_corrupt_rejected = all_corrupt_rejected && err == .InvalidFileFormatError
	}
	_, extended_err := rifle.base_file_decode(extended)

	// Assert
	testing.expect(t, all_truncated_rejected)
	testing.expect(t, all_corrupt_rejected)
	testing.expect_value(t, extended_err, rifle.RifleError.InvalidFileFormatError)
}

@(test)
given_log_metadata_when_base_file_is_created_then_it_can_be_read_from_disk :: proc(t: ^testing.T) {
	// Arrange
	directory, directory_err := os.make_directory_temp("", "rifle-base-file-*", context.allocator)
	if !testing.expect(t, directory_err == nil) {
		return
	}
	defer os.remove_all(directory)
	defer delete(directory)
	c_directory := strings.clone_to_cstring(directory)
	defer delete(c_directory)
	path := strings.concatenate({directory, "/", rifle.BASE_FILENAME})
	defer delete(path)
	c_path := strings.clone_to_cstring(path)
	defer delete(c_path)
	log: rifle.Log
	log.config = rifle.DefaultLogConfig
	log.config.log_path = c_directory
	log.config.file_size_bytes = 8192
	log.config.schema = {record_size = 8, fields = []rifle.SchemaField{{name = "value", type = .I64, size = 8}}}

	// Act
	create_err := rifle.create_base_file(&log)
	metadata, read_err := rifle.read_base_file(c_path)
	defer rifle.schema_destroy(metadata.schema)

	// Assert
	testing.expect_value(t, create_err, rifle.RifleError.None)
	testing.expect_value(t, read_err, rifle.RifleError.None)
	testing.expect_value(t, metadata.record_size, i64(8))
	testing.expect_value(t, metadata.file_size, i64(8192))
	testing.expect_value(t, metadata.head, i64(0))
	testing.expect_value(t, metadata.tail, i64(0))
	testing.expect_value(t, metadata.schema.fields[0], log.config.schema.fields[0])
}

@(test)
given_missing_base_file_when_read_then_file_operation_error_is_returned :: proc(t: ^testing.T) {
	// Arrange
	path: cstring = "/tmp/rifle-file-that-does-not-exist/base.rfl"

	// Act
	_, err := rifle.read_base_file(path)

	// Assert
	testing.expect_value(t, err, rifle.RifleError.FileOperationError)
}

@(test)
given_valid_metadata_bytes_and_failing_allocator_when_decoded_then_allocator_error_is_returned :: proc(t: ^testing.T) {
	// Arrange
	encoded, encode_err := rifle.base_file_encode({
		record_size = 8,
		file_size = 4096,
		schema = {record_size = 8, fields = []rifle.SchemaField{{name = "value", type = .U64}}},
	})
	if !testing.expect_value(t, encode_err, rifle.RifleError.None) {
		return
	}
	defer delete(encoded)
	allocator := runtime.nil_allocator()

	// Act
	metadata, err := rifle.base_file_decode(encoded, allocator)

	// Assert
	testing.expect_value(t, err, rifle.RifleError.AllocatorError)
	testing.expect(t, metadata.schema.fields == nil)
}
