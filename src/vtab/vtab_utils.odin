package vtab

import "core:fmt"
import "core:strings"
import "core:sys/linux"
import "rifle:rifle"
import sqlite "rifle:vendor/sqlite_ext"

// Builds a table declaration string from a RecordSchema
create_table_sql :: proc(schema: rifle.RecordSchema, table_name := "rifle", allocator := context.allocator) -> (sql: cstring, err: rifle.SchemaError) {
	if len(schema.fields) == 0 {
		return nil, .NoFields
	}
	if !rifle.is_valid_field_name(table_name) {
		return nil, .InvalidName
	}

	prefix :: "CREATE TABLE \""
	size := 1 + len(prefix) + len(table_name) + len("\" (") + len(");")
	for field, i in schema.fields {
		if !rifle.is_valid_field_name(field.name) {
			return nil, .InvalidName
		}
		type_name := get_sqlite_type(field.type)
		if type_name == "" {
			return nil, .InvalidType
		}
		extra := len(field.name) + len(type_name) + 3 // quotes and space
		if i > 0 {
			extra += 2
		}
		if extra > max(int) - size {
			return nil, .InvalidSize
		}
		size += extra
	}

	// Reserve the complete statement and null terminator.
	builder, alloc_err := strings.builder_make(0, size, allocator)
	if alloc_err != nil {
		return nil, .AllocatorError
	}
	strings.write_string(&builder, prefix)
	strings.write_string(&builder, table_name)
	strings.write_string(&builder, "\" (")
	for field, i in schema.fields {
		if i > 0 {
			strings.write_string(&builder, ", ")
		}
		strings.write_string(&builder, "\"")
		strings.write_string(&builder, field.name)
		strings.write_string(&builder, "\" ")
		strings.write_string(&builder, get_sqlite_type(field.type))
	}
	strings.write_string(&builder, ");")
	return strings.unsafe_to_cstring(&builder), .None
}

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

// Opens files covering record range
open_files :: proc(cursor: ^Cursor, min_index, max_index: i64) -> i32 {
	vtab := cast(^Vtab)cursor.pVtab
	first_file := min_index * vtab.log_data.record_size / vtab.log_data.file_size
	last_file := max_index * vtab.log_data.record_size / vtab.log_data.file_size
	log_path := string(vtab.log_path)
	directory := log_path[:strings.last_index_byte(log_path, '/') + 1]
	path_buffer := make([]u8, len(directory) + len(rifle.DATA_PREFIX) + 20 + len(rifle.FILE_EXTENSION) + 1)
	defer delete(path_buffer)

	for file_index := first_file; file_index <= last_file; file_index += 1 {
		if _, found := cursor.files[file_index]; found {
			continue
		}
		path := fmt.bprintf(path_buffer[:len(path_buffer) - 1], "%s%s%020d%s", directory, rifle.DATA_PREFIX, file_index, rifle.FILE_EXTENSION)
		path_buffer[len(path)] = 0
		fd, err := linux.open(cstring(raw_data(path_buffer)), {.CLOEXEC, .DIRECT})
		if err != nil {
			return sqlite.CANTOPEN
		}
		cursor.files[file_index] = fd
	}
	return sqlite.OK
}

read_page_at :: proc(cursor: ^Cursor, page_index, file_size: i64) -> i32 {
	page_start := page_index * i64(len(cursor.current_page.data))
	fd, found := cursor.files[page_start / file_size]
	if !found {
		return sqlite.CANTOPEN
	}
	file_offset := page_start % file_size

	cursor.current_page.index = -1 //Incase of failed read
	for {
		n, err := linux.pread(linux.Fd(fd), cursor.current_page.data, file_offset)
		if err == .EINTR {
			continue
		}
		if err != nil {
			return sqlite.IOERR_READ
		}
		if n != len(cursor.current_page.data) {
			return sqlite.IOERR_SHORT_READ
		}
		break
	}
	cursor.current_page.index = page_index
	return sqlite.OK
}
