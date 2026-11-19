package unit

import "base:runtime"
import "core:testing"
import rifle "rifle:rifle"

@(test)
given_supported_field_types_when_width_is_requested_then_width_and_sizing_are_correct :: proc(t: ^testing.T) {
	// Arrange
	cases := [?]struct {
		type:  rifle.FieldType,
		width: i64,
		sized: bool,
	}{
		{.I8, 1, false},
		{.U8, 1, false},
		{.Bool, 1, false},
		{.I16, 2, false},
		{.U16, 2, false},
		{.I32, 4, false},
		{.U32, 4, false},
		{.F32, 4, false},
		{.I64, 8, false},
		{.U64, 8, false},
		{.F64, 8, false},
		{.Bytes, 0, true},
		{.Text, 0, true},
		{.Invalid, 0, false},
	}

	// Act
	for test_case in cases {
		width, sized := rifle.field_type_width(test_case.type)

		// Assert
		testing.expect_value(t, width, test_case.width)
		testing.expect_value(t, sized, test_case.sized)
	}
}

@(test)
given_field_names_when_validated_then_only_identifiers_are_accepted :: proc(t: ^testing.T) {
	// Arrange
	valid := [?]string{"value", "Value_2", "_internal", "a0"}
	invalid := [?]string{"", "2value", "has space", "dash-name", "naïve"}

	// Act
	valid_results: [len(valid)]bool
	invalid_results: [len(invalid)]bool
	for name, i in valid {
		valid_results[i] = rifle.is_valid_field_name(name)
	}
	for name, i in invalid {
		invalid_results[i] = rifle.is_valid_field_name(name)
	}

	// Assert
	for result in valid_results {
		testing.expect(t, result)
	}
	for result in invalid_results {
		testing.expect(t, !result)
	}
}

@(test)
given_valid_schema_when_validated_then_no_field_is_rejected :: proc(t: ^testing.T) {
	// Arrange
	fields := []rifle.SchemaField{
		{name = "id", type = .U64, offset = 0},
		{name = "label", type = .Text, offset = 8, size = 12},
	}

	// Act
	bad_field, err := rifle.schema_validate(20, fields)

	// Assert
	testing.expect_value(t, bad_field, -1)
	testing.expect_value(t, err, rifle.SchemaError.None)
}

@(test)
given_invalid_schemas_when_validated_then_precise_error_and_field_are_returned :: proc(t: ^testing.T) {
	// Arrange
	valid := rifle.SchemaField{name = "value", type = .U64, offset = 0}
	cases := [?]struct {
		name:               string,
		record_size:        i64,
		fields:             []rifle.SchemaField,
		expected_bad_field: int,
		expected_error:     rifle.SchemaError,
	}{
		{"record size", 0, []rifle.SchemaField{valid}, -1, .InvalidRecordSize},
		{"empty fields", 8, nil, -1, .NoFields},
		{"field type", 8, []rifle.SchemaField{{name = "value", type = .Invalid}}, 0, .InvalidType},
		{"field name", 8, []rifle.SchemaField{{name = "bad name", type = .U64}}, 0, .InvalidName},
		{"field size", 8, []rifle.SchemaField{{name = "value", type = .Bytes, size = 0}}, 0, .InvalidSize},
		{"field bounds", 8, []rifle.SchemaField{{name = "value", type = .U64, offset = 1}}, 0, .FieldOutOfBounds},
		{"duplicate name", 16, []rifle.SchemaField{valid, {name = "VALUE", type = .U64, offset = 8}}, 1, .DuplicateName},
		{"overlap", 16, []rifle.SchemaField{valid, {name = "other", type = .U64, offset = 4}}, 1, .OverlappingFields},
	}

	// Act / Assert
	for test_case in cases {
		bad_field, err := rifle.schema_validate(test_case.record_size, test_case.fields)
		testing.expectf(
			t,
			bad_field == test_case.expected_bad_field,
			"%s: expected bad field %d, got %d",
			test_case.name,
			test_case.expected_bad_field,
			bad_field,
		)
		testing.expectf(
			t,
			err == test_case.expected_error,
			"%s: expected error %v, got %v",
			test_case.name,
			test_case.expected_error,
			err,
		)
	}
}

@(test)
given_mutable_schema_input_when_created_then_schema_owns_a_normalized_copy :: proc(t: ^testing.T) {
	// Arrange
	name_bytes := [5]u8{'v', 'a', 'l', 'u', 'e'}
	fields := []rifle.SchemaField{{name = string(name_bytes[:]), type = .I64}}

	// Act
	schema, bad_field, err := rifle.schema_create(8, fields)
	defer rifle.schema_destroy(schema)
	name_bytes[0] = 'X'
	fields[0].offset = 7

	// Assert
	testing.expect_value(t, bad_field, -1)
	testing.expect_value(t, err, rifle.SchemaError.None)
	testing.expect_value(t, schema.record_size, i64(8))
	testing.expect_value(t, schema.fields[0].name, "value")
	testing.expect_value(t, schema.fields[0].offset, i64(0))
	testing.expect_value(t, schema.fields[0].size, i64(8))
}

@(test)
given_valid_schema_when_encoded_and_decoded_then_disk_layout_and_values_round_trip :: proc(t: ^testing.T) {
	// Arrange
	schema := rifle.RecordSchema{
		record_size = 20,
		fields = []rifle.SchemaField{
			{name = "id", type = .U64, offset = 0, size = 8},
			{name = "name", type = .Text, offset = 8, size = 12},
		},
	}
	expected := [64]u8{
		2, 0, 0, 0, 0, 0, 0, 0,
		2, 0, 0, 0, 0, 0, 0, 0, 'i', 'd', 13,
		0, 0, 0, 0, 0, 0, 0, 0,
		8, 0, 0, 0, 0, 0, 0, 0,
		4, 0, 0, 0, 0, 0, 0, 0, 'n', 'a', 'm', 'e', 41,
		8, 0, 0, 0, 0, 0, 0, 0,
		12, 0, 0, 0, 0, 0, 0, 0,
	}

	// Act
	encoded, encode_err := rifle.schema_encode(schema)
	defer delete(encoded)
	decoded, decode_err := rifle.schema_decode(expected[:], 20)
	defer rifle.schema_destroy(decoded)

	// Assert
	testing.expect_value(t, encode_err, rifle.SchemaError.None)
	testing.expect_value(t, string(encoded), string(expected[:]))
	testing.expect_value(t, decode_err, rifle.SchemaError.None)
	testing.expect_value(t, decoded.record_size, i64(20))
	for field, i in decoded.fields {
		testing.expect_value(t, field, schema.fields[i])
	}
}

@(test)
given_truncated_or_hostile_schema_bytes_when_decoded_then_input_is_rejected :: proc(t: ^testing.T) {
	// Arrange
	valid, encode_err := rifle.schema_encode({record_size = 8, fields = []rifle.SchemaField{{name = "value", type = .U64}}})
	if !testing.expect_value(t, encode_err, rifle.SchemaError.None) {
		return
	}
	defer delete(valid)
	hostile_count := make([]u8, len(valid))
	defer delete(hostile_count)
	copy(hostile_count, valid)
	for &byte in hostile_count[:8] {
		byte = 0xff
	}
	hostile_count[7] = 0x7f
	hostile_name := make([]u8, len(valid))
	defer delete(hostile_name)
	copy(hostile_name, valid)
	for &byte in hostile_name[8:16] {
		byte = 0xff
	}

	// Act
	all_truncated_rejected := true
	for end in 0 ..< len(valid) {
		decoded, err := rifle.schema_decode(valid[:end], 8)
		rifle.schema_destroy(decoded)
		all_truncated_rejected = all_truncated_rejected && err != .None
	}
	_, count_err := rifle.schema_decode(hostile_count, 8)
	_, name_err := rifle.schema_decode(hostile_name, 8)

	// Assert
	testing.expect(t, all_truncated_rejected)
	testing.expect_value(t, count_err, rifle.SchemaError.Truncated)
	testing.expect_value(t, name_err, rifle.SchemaError.InvalidName)
}

@(test)
given_failing_allocator_when_schema_is_created_or_encoded_then_allocator_error_is_returned :: proc(t: ^testing.T) {
	// Arrange
	fields := []rifle.SchemaField{{name = "value", type = .U64}}
	allocator := runtime.nil_allocator()

	// Act
	created, bad_field, create_err := rifle.schema_create(8, fields, allocator)
	encoded, encode_err := rifle.schema_encode({record_size = 8, fields = fields}, allocator)

	// Assert
	testing.expect(t, created.fields == nil)
	testing.expect_value(t, bad_field, -1)
	testing.expect_value(t, create_err, rifle.SchemaError.AllocatorError)
	testing.expect(t, encoded == nil)
	testing.expect_value(t, encode_err, rifle.SchemaError.AllocatorError)
}

@(test)
given_schema_with_wide_offsets_when_encoded_and_decoded_then_i64_values_are_preserved :: proc(t: ^testing.T) {
	// Arrange
	fields := []rifle.SchemaField{
		{name = "large", type = .Bytes, offset = 1 << 33, size = 1 << 34},
		{name = "last", type = .I8, offset = (1 << 33) + (1 << 34), size = 1},
	}
	original := rifle.RecordSchema{record_size = 1 << 35, fields = fields}

	// Act
	encoded, encode_err := rifle.schema_encode(original)
	defer delete(encoded)
	decoded, decode_err := rifle.schema_decode(encoded, original.record_size)
	defer rifle.schema_destroy(decoded)

	// Assert
	testing.expect_value(t, encode_err, rifle.SchemaError.None)
	testing.expect_value(t, decode_err, rifle.SchemaError.None)
	testing.expect_value(t, decoded.record_size, original.record_size)
	for field, i in decoded.fields {
		testing.expect_value(t, field, original.fields[i])
	}
}

@(test)
given_fixed_width_field_sizes_when_validated_then_zero_or_exact_width_is_accepted_and_other_sizes_are_rejected :: proc(t: ^testing.T) {
	// Arrange
	zero_size := []rifle.SchemaField{{name = "value", type = .U32, size = 0}}
	exact_size := []rifle.SchemaField{{name = "value", type = .U32, size = 4}}
	wrong_size := []rifle.SchemaField{{name = "value", type = .U32, size = 8}}

	// Act
	zero_field, zero_err := rifle.schema_validate(4, zero_size)
	exact_field, exact_err := rifle.schema_validate(4, exact_size)
	wrong_field, wrong_err := rifle.schema_validate(8, wrong_size)

	// Assert
	testing.expect_value(t, zero_field, -1)
	testing.expect_value(t, zero_err, rifle.SchemaError.None)
	testing.expect_value(t, exact_field, -1)
	testing.expect_value(t, exact_err, rifle.SchemaError.None)
	testing.expect_value(t, wrong_field, 0)
	testing.expect_value(t, wrong_err, rifle.SchemaError.InvalidSize)
}

@(test)
given_adjacent_fields_when_validated_then_touching_boundaries_do_not_count_as_overlap :: proc(t: ^testing.T) {
	// Arrange
	fields := []rifle.SchemaField{
		{name = "first", type = .U32, offset = 0},
		{name = "second", type = .Bytes, offset = 4, size = 4},
		{name = "third", type = .U64, offset = 8},
	}

	// Act
	bad_field, err := rifle.schema_validate(16, fields)

	// Assert
	testing.expect_value(t, bad_field, -1)
	testing.expect_value(t, err, rifle.SchemaError.None)
}

@(test)
given_schema_fields_and_names_when_arena_size_is_calculated_then_each_owned_value_is_accounted_for :: proc(t: ^testing.T) {
	// Arrange
	one := rifle.RecordSchema{fields = []rifle.SchemaField{{name = "a"}}}
	two := rifle.RecordSchema{fields = []rifle.SchemaField{{name = "a"}, {name = "longer"}}}

	// Act
	one_size := rifle.schema_arena_size(one)
	two_size := rifle.schema_arena_size(two)

	// Assert
	testing.expect_value(t, one_size, i64(size_of(rifle.SchemaField) + align_of(rifle.SchemaField) + 1 + align_of(u8)))
	testing.expect_value(t, two_size - one_size, i64(size_of(rifle.SchemaField) + len("longer") + align_of(u8)))
}
