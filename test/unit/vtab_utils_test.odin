package unit

import "base:runtime"
import "core:sys/linux"
import "core:testing"
import rifle "rifle:rifle"
import sqlite "rifle:vendor/sqlite_ext"
import vtab "rifle:vtab"

@(test)
given_rifle_field_types_when_mapped_to_sqlite_then_each_supported_affinity_is_returned :: proc(t: ^testing.T) {
	// Arrange
	cases := [?]struct {
		type:     rifle.FieldType,
		expected: string,
	}{
		{.I8, "INTEGER"},
		{.I16, "INTEGER"},
		{.I32, "INTEGER"},
		{.I64, "INTEGER"},
		{.U8, "INTEGER"},
		{.U16, "INTEGER"},
		{.U32, "INTEGER"},
		{.U64, "INTEGER"},
		{.Bool, "INTEGER"},
		{.F32, "REAL"},
		{.F64, "REAL"},
		{.Bytes, "BLOB"},
		{.Text, "TEXT"},
		{.Invalid, ""},
	}

	// Act
	actual: [len(cases)]string
	for test_case, i in cases {
		actual[i] = vtab.get_sqlite_type(test_case.type)
	}

	// Assert
	for test_case, i in cases {
		testing.expect_value(t, actual[i], test_case.expected)
	}
}

@(test)
given_record_schema_when_table_sql_is_created_then_identifiers_are_quoted_and_affinities_are_preserved :: proc(t: ^testing.T) {
	// Arrange
	schema := rifle.RecordSchema{
		record_size = 20,
		fields = []rifle.SchemaField{
			{name = "id", type = .U64},
			{name = "reading", type = .F64, offset = 8},
			{name = "label", type = .Text, offset = 16, size = 4},
		},
	}

	// Act
	sql, err := vtab.create_table_sql(schema, "events")
	defer delete(sql)

	// Assert
	testing.expect_value(t, err, rifle.SchemaError.None)
	testing.expect_value(t, string(sql), `CREATE TABLE "events" ("id" INTEGER, "reading" REAL, "label" TEXT);`)
}

@(test)
given_invalid_table_declarations_when_sql_is_created_then_precise_schema_error_is_returned :: proc(t: ^testing.T) {
	// Arrange
	valid := rifle.RecordSchema{record_size = 8, fields = []rifle.SchemaField{{name = "value", type = .U64}}}
	no_fields: rifle.RecordSchema
	invalid_field := rifle.RecordSchema{record_size = 8, fields = []rifle.SchemaField{{name = "bad name", type = .U64}}}
	invalid_type := rifle.RecordSchema{record_size = 8, fields = []rifle.SchemaField{{name = "value", type = .Invalid}}}

	// Act
	_, no_fields_err := vtab.create_table_sql(no_fields)
	_, table_name_err := vtab.create_table_sql(valid, "bad name")
	_, field_name_err := vtab.create_table_sql(invalid_field)
	_, field_type_err := vtab.create_table_sql(invalid_type)

	// Assert
	testing.expect_value(t, no_fields_err, rifle.SchemaError.NoFields)
	testing.expect_value(t, table_name_err, rifle.SchemaError.InvalidName)
	testing.expect_value(t, field_name_err, rifle.SchemaError.InvalidName)
	testing.expect_value(t, field_type_err, rifle.SchemaError.InvalidType)
}

@(test)
given_valid_table_declaration_and_failing_allocator_when_sql_is_created_then_allocator_error_is_returned :: proc(t: ^testing.T) {
	// Arrange
	schema := rifle.RecordSchema{record_size = 8, fields = []rifle.SchemaField{{name = "value", type = .U64}}}
	allocator := runtime.nil_allocator()

	// Act
	sql, err := vtab.create_table_sql(schema, allocator = allocator)

	// Assert
	testing.expect_value(t, err, rifle.SchemaError.AllocatorError)
	testing.expect(t, sql == nil)
}

@(test)
given_complete_file_page_when_read_then_page_bytes_and_index_are_updated :: proc(t: ^testing.T) {
	// Arrange
	fd, create_err := linux.memfd_create("rifle-vtab-page-test", {.CLOEXEC})
	if !testing.expect_value(t, create_err, linux.Errno.NONE) {
		return
	}
	defer linux.close(fd)
	input: [32]u8
	for &value, i in input {
		value = u8(i + 1)
	}
	written, write_err := linux.pwrite(fd, input[:], 0)
	if !testing.expect_value(t, write_err, linux.Errno.NONE) || !testing.expect_value(t, written, len(input)) {
		return
	}
	output: [32]u8
	cursor := vtab.Cursor{current_page = {index = -1, data = output[:]}, files = make(map[i64]linux.Fd)}
	defer delete(cursor.files)
	cursor.files[0] = fd

	// Act
	rc := vtab.read_page_at(&cursor, 0, 64)

	// Assert
	testing.expect_value(t, rc, i32(sqlite.OK))
	testing.expect_value(t, cursor.current_page.index, i64(0))
	testing.expect_value(t, output, input)
}

@(test)
given_short_file_page_when_read_then_short_read_is_reported_and_page_remains_invalid :: proc(t: ^testing.T) {
	// Arrange
	fd, create_err := linux.memfd_create("rifle-vtab-short-page-test", {.CLOEXEC})
	if !testing.expect_value(t, create_err, linux.Errno.NONE) {
		return
	}
	defer linux.close(fd)
	input: [16]u8
	written, write_err := linux.pwrite(fd, input[:], 0)
	if !testing.expect_value(t, write_err, linux.Errno.NONE) || !testing.expect_value(t, written, len(input)) {
		return
	}
	output: [32]u8
	cursor := vtab.Cursor{current_page = {index = 7, data = output[:]}, files = make(map[i64]linux.Fd)}
	defer delete(cursor.files)
	cursor.files[0] = fd

	// Act
	rc := vtab.read_page_at(&cursor, 0, 64)

	// Assert
	testing.expect_value(t, rc, i32(sqlite.IOERR_SHORT_READ))
	testing.expect_value(t, cursor.current_page.index, i64(-1))
}
