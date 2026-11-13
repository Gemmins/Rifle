package rifle

import "core:mem"
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

// Field description passed to log_init from user
// This should always be 24 bytes
FieldDesc :: struct {
	name:   cstring,
	offset: u32, // byte offset within the record
	size:   u32, // 0 unless bytes/text
	type:   FieldType,
	_pad:   [7]u8, // maybe just make FieldType a u64 insted
}

SchemaField :: struct {
	name:   string,
	type:   FieldType,
	offset: i64,
	size:   i64, // actual field size
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

schema_create :: proc(record_size: i64, descs: []FieldDesc, allocator := context.allocator) -> (s: RecordSchema, bad_field: int, err: SchemaError) {
	bad_field = -1

	if record_size <= 0 {
		return {}, -1, .InvalidRecordSize
	}
	if len(descs) == 0 {
		return {}, -1, .NoFields
	}

	fields, alloc_err := make([]SchemaField, len(descs), allocator)
	if alloc_err != nil {
		return {}, -1, .AllocatorError
	}
	defer if err != .None {
		schema_destroy({record_size, fields}, allocator)
	}

	for desc, i in descs {
		width, sized := field_type_width(desc.type)
		if desc.type == .Invalid || width == 0 && !sized {
			return {}, i, .InvalidType
		}

		size := i64(desc.size)
		if sized {
			if size == 0 {
				return {}, i, .InvalidSize
			}
		} else {
			if size != 0 && size != width {
				return {}, i, .InvalidSize
			}
			size = width
		}

		offset := i64(desc.offset)
		if offset + size > record_size {
			return {}, i, .FieldOutOfBounds
		}

		name := string(desc.name)
		if !is_valid_field_name(name) {
			return {}, i, .InvalidName
		}
		for j in 0 ..< i {
			if strings.equal_fold(fields[j].name, name) {
				return {}, i, .DuplicateName
			}
		}

		cloned, clone_err := strings.clone(name, allocator)
		if clone_err != nil {
			return {}, i, .AllocatorError
		}

		fields[i] = SchemaField {
			name   = cloned,
			type   = desc.type,
			offset = offset,
			size   = size,
		}
	}

	for i in 0 ..< len(fields) {
		a := fields[i]
		for j in i + 1 ..< len(fields) {
			b := fields[j]
			if a.offset < b.offset + b.size && b.offset < a.offset + a.size {
				return {}, j, .OverlappingFields
			}
		}
	}

	return RecordSchema{record_size = record_size, fields = fields}, -1, .None
}

schema_destroy :: proc(s: RecordSchema, allocator := context.allocator) {
	for field in s.fields {
		delete(field.name, allocator)
	}
	delete(s.fields, allocator)
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
	if len(name) == 0 || len(name) > MAX_FIELD_NAME_LEN {
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
	if s.record_size <= 0 {
		return nil, .InvalidRecordSize
	}
	if len(s.fields) == 0 {
		return nil, .NoFields
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
	put :: proc(buf: []u8, w: ^int, value: $T) {
		v := value
		copy(buf[w^:], mem.ptr_to_bytes(&v))
		w^ += size_of(T)
	}
	put(buf, &w, i64le(len(s.fields)))
	for field in s.fields {
		put(buf, &w, i64le(len(field.name)))
		copy(buf[w:], field.name)
		w += len(field.name)
		put(buf, &w, u8(field.type))
		put(buf, &w, i64le(field.offset))
		put(buf, &w, i64le(field.size))
	}
	return buf, .None
}

// Reads the serialised schema
schema_decode :: proc(data: []u8, record_size: i64, allocator := context.allocator) -> (s: RecordSchema, err: SchemaError) {
	if len(data) < SCHEMA_PREAMBLE_SIZE {
		return {}, .Truncated
	}

	r: int
	get :: proc(data: []u8, r: ^int, $T: typeid) -> T {
		v: T
		copy(mem.ptr_to_bytes(&v), data[r^:][:size_of(T)])
		r^ += size_of(T)
		return v
	}
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

	for &field, i in fields {
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

		width, sized := field_type_width(field.type)
		if width == 0 && !sized {
			return {}, .InvalidType
		}
		if field.size <= 0 || !sized && field.size != width {
			return {}, .InvalidSize
		}
		if field.offset < 0 || field.offset > record_size || field.size > record_size - field.offset {
			return {}, .FieldOutOfBounds
		}
		if !is_valid_field_name(name) {
			return {}, .InvalidName
		}
		for previous in fields[:i] {
			if strings.equal_fold(previous.name, name) {
				return {}, .DuplicateName
			}
			if field.offset < previous.offset + previous.size && previous.offset < field.offset + field.size {
				return {}, .OverlappingFields
			}
		}
		cloned, clone_err := strings.clone(name, allocator)
		if clone_err != nil {
			return {}, .AllocatorError
		}
		field.name = cloned
	}
	return {record_size, fields}, .None
}
