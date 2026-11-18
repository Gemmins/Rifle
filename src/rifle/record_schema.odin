package rifle

import "core:strings"


FieldType :: enum u8 {
	Invalid = 0,
	I8      = 1,
	I16     = 2,
	I32     = 3,
	I64     = 4,
	U8      = 10,
	U16     = 11,
	U32     = 12,
	U64     = 13,
	F32     = 20,
	F64     = 21,
	Bool    = 30,
	// Caller-sized types; `size` required.
	Bytes   = 40, // fixed-length blob
	Text    = 41, // fixed-length UTF-8
}

MAX_FIELD_NAME_LEN :: int(max(u16))

SchemaField :: struct {
	name:   string,
	type:   FieldType,
	offset: i64,
	size:   i64,
}

RecordSchema :: struct {
	record_size: i64,
	fields:      []SchemaField,
}

SchemaError :: enum {
	None,
	// Validation
	NoFields,
	InvalidRecordSize,
	InvalidType,
	InvalidName,
	DuplicateName,
	InvalidSize,
	FieldOutOfBounds,
	OverlappingFields,
	AllocatorError,
	// On disk
	Truncated,
}

// Validates a schema
schema_validate :: proc(record_size: i64, fields: []SchemaField) -> (bad_field: int, err: SchemaError) {
	if record_size <= 0 {
		return -1, .InvalidRecordSize
	}
	if len(fields) <= 0 || raw_data(fields) == nil {
		return -1, .NoFields
	}
	for field, i in fields {
		width, sized := field_type_width(field.type)
		if width == 0 && !sized {
			return i, .InvalidType
		}
		size := sized ? field.size : width
		if size <= 0 || !sized && field.size != 0 && field.size != width {
			return i, .InvalidSize
		}
		if field.offset < 0 || field.offset > record_size || size > record_size - field.offset {
			return i, .FieldOutOfBounds
		}
		if !is_valid_field_name(field.name) {
			return i, .InvalidName
		}
		for previous in fields[:i] {
			if strings.equal_fold(previous.name, field.name) {
				return i, .DuplicateName
			}
			previous_width, previous_sized := field_type_width(previous.type)
			previous_size := previous_sized ? previous.size : previous_width
			if field.offset < previous.offset + previous_size && previous.offset < field.offset + size {
				return i, .OverlappingFields
			}
		}
	}
	return -1, .None
}

// Creates a copy of a schema, along with validation
schema_create :: proc(record_size: i64, input: []SchemaField, allocator := context.allocator) -> (s: RecordSchema, bad_field: int, err: SchemaError) {
	bad_field, err = schema_validate(record_size, input)
	if err != .None {
		return
	}
	fields, alloc_err := make([]SchemaField, len(input), allocator)
	if alloc_err != nil {
		return {}, -1, .AllocatorError
	}
	defer if err != .None {
		schema_destroy({record_size, fields}, allocator)
	}
	for field, i in input {
		name, clone_err := strings.clone(field.name, allocator)
		if clone_err != nil {
			return {}, i, .AllocatorError
		}
		fields[i] = field
		fields[i].name = name
		width, sized := field_type_width(field.type)
		if !sized {
			fields[i].size = width
		}
	}
	return {record_size, fields}, -1, .None
}

schema_destroy :: proc(s: RecordSchema, allocator := context.allocator) {
	for field in s.fields {
		delete(field.name, allocator)
	}
	delete(s.fields, allocator)
}

schema_arena_size :: proc(schema: RecordSchema) -> i64 {
	size := i64(len(schema.fields)) * size_of(SchemaField)
	size += align_of(SchemaField)
	for field in schema.fields {
		size += i64(len(field.name)) + align_of(u8)
	}
	return size
}

field_type_width :: proc(type: FieldType) -> (width: i64, sized: bool) {
	switch type {
	case .I8, .U8, .Bool:
		return 1, false
	case .I16, .U16:
		return 2, false
	case .I32, .U32, .F32:
		return 4, false
	case .I64, .U64, .F64:
		return 8, false
	case .Bytes, .Text:
		return 0, true
	case .Invalid:
		return 0, false
	}
	return 0, false
}

is_valid_field_name :: proc(name: string) -> bool {
	if len(name) <= 0 || len(name) > MAX_FIELD_NAME_LEN || raw_data(name) == nil {
		return false
	}
	for c, i in name {
		switch {
		case c == '_':
		case c >= 'a' && c <= 'z', c >= 'A' && c <= 'Z':
		case c >= '0' && c <= '9':
			if i == 0 {
				return false
			}
		case:
			return false
		}
	}
	return true
}

// field_count i64
// per field: name_length i64, name bytes, type u8, offset i64, size i64
SCHEMA_PREAMBLE_SIZE :: 8
SCHEMA_FIELD_SIZE :: 8 + 1 + 8 + 8

// Serialises a valid schema into a buffer
schema_encode :: proc(s: RecordSchema, allocator := context.allocator) -> (data: []u8, err: SchemaError) {
	_, err = schema_validate(s.record_size, s.fields)
	if err != .None {
		return nil, err
	}
	size := SCHEMA_PREAMBLE_SIZE
	for field in s.fields {
		if len(field.name) > max(int) - size - SCHEMA_FIELD_SIZE {
			return nil, .InvalidSize
		}
		size += SCHEMA_FIELD_SIZE + len(field.name)
	}

	buf, alloc_err := make([]u8, size, allocator)
	if alloc_err != nil {
		return nil, .AllocatorError
	}

	w: int
	put(buf, &w, i64le(len(s.fields)))
	for field in s.fields {
		put(buf, &w, i64le(len(field.name)))
		copy(buf[w:], field.name)
		w += len(field.name)
		put(buf, &w, u8(field.type))
		put(buf, &w, i64le(field.offset))
		width, sized := field_type_width(field.type)
		put(buf, &w, i64le(sized ? field.size : width))
	}
	return buf, .None
}

// Reads the serialised schema
schema_decode :: proc(data: []u8, record_size: i64, allocator := context.allocator) -> (s: RecordSchema, err: SchemaError) {
	if len(data) < SCHEMA_PREAMBLE_SIZE {
		return {}, .Truncated
	}

	r: int
	field_count := i64(get(data, &r, i64le))
	if record_size <= 0 {
		return {}, .InvalidRecordSize
	}
	if field_count <= 0 {
		return {}, .NoFields
	}
	// Bound the allocation by the bytes available before converting to int.
	if field_count > i64((len(data) - r) / SCHEMA_FIELD_SIZE) {
		return {}, .Truncated
	}
	fields, alloc_err := make([]SchemaField, int(field_count), allocator)
	if alloc_err != nil {
		return {}, .AllocatorError
	}
	defer if err != .None {
		schema_destroy({record_size, fields}, allocator)
	}
	for &field in fields {
		if len(data) - r < SCHEMA_FIELD_SIZE {
			return {}, .Truncated
		}
		name_len := i64(get(data, &r, i64le))
		if name_len <= 0 || name_len > i64(MAX_FIELD_NAME_LEN) {
			return {}, .InvalidName
		}
		if name_len > i64(len(data) - r - (SCHEMA_FIELD_SIZE - 8)) {
			return {}, .Truncated
		}
		name := string(data[r:][:int(name_len)])
		r += int(name_len)
		field.type = FieldType(get(data, &r, u8))
		field.offset = i64(get(data, &r, i64le))
		field.size = i64(get(data, &r, i64le))

		cloned, clone_err := strings.clone(name, allocator)
		if clone_err != nil {
			return {}, .AllocatorError
		}
		field.name = cloned
	}
	_, err = schema_validate(record_size, fields)
	if err != .None {
		return {}, err
	}
	for &field in fields {
		width, sized := field_type_width(field.type)
		if !sized {
			field.size = width
		}
	}
	return {record_size, fields}, .None
}
