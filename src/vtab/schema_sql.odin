package vtab

import "core:strings"
import "rifle:rifle"

// Builds a table declaration string from a RecordSchema
create_table_sql :: proc(schema: rifle.RecordSchema, table_name := "rifle", allocator := context.allocator) -> (sql: cstring, err: rifle.SchemaError) {
	if len(schema.fields) == 0 {return nil, .NoFields}
	if !rifle.is_valid_field_name(table_name) {return nil, .InvalidName}

	prefix :: "CREATE TABLE \""
	size := 1 + len(prefix) + len(table_name) + len("\" (") + len(");")
	for field, i in schema.fields {
		if !rifle.is_valid_field_name(field.name) {return nil, .InvalidName}
		type_name := get_sqlite_type(field.type)
		if type_name == "" {return nil, .InvalidType}
		extra := len(field.name) + len(type_name) + 3 // quotes and space
		if i > 0 {extra += 2}
		if extra > max(int) - size {return nil, .InvalidSize}
		size += extra
	}

	// Reserve the complete statement and null terminator.
	builder, alloc_err := strings.builder_make(0, size, allocator)
	if alloc_err != nil {return nil, .AllocatorError}
	strings.write_string(&builder, prefix)
	strings.write_string(&builder, table_name)
	strings.write_string(&builder, "\" (")
	for field, i in schema.fields {
		if i > 0 {strings.write_string(&builder, ", ")}
		strings.write_string(&builder, "\"")
		strings.write_string(&builder, field.name)
		strings.write_string(&builder, "\" ")
		strings.write_string(&builder, get_sqlite_type(field.type))
	}
	strings.write_string(&builder, ");")
	return strings.unsafe_to_cstring(&builder), .None
}

@(private)
get_sqlite_type :: proc(type: rifle.FieldType) -> string {
	switch type {
	case .I8, .I16, .I32, .I64, .U8, .U16, .U32, .U64, .Bool:
		return "INTEGER"
	case .F32, .F64:
		return "REAL"
	case .Bytes:
		return "BLOB"
	case .Text:
		return "TEXT"
	case .Invalid:
		return ""
	}
	return ""
}
