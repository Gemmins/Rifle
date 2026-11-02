package test

import rifle "rifle:rifle"
import "core:testing"

@(test)
schema_disk_layout :: proc(t: ^testing.T) {
	// An independent fixture for the layout documented in base_file.odin.
	data := [42]u8{
		8, 0, 0, 0, 0, 0, 0, 0, // record size
		1, 0, 0, 0, 0, 0, 0, 0, // field count
		1, 0, 0, 0, 0, 0, 0, 0, // name length
		'x', 13,                 // name, U64
		0, 0, 0, 0, 0, 0, 0, 0, // offset
		8, 0, 0, 0, 0, 0, 0, 0, // size
	}

	schema, err := rifle.schema_decode(data[:])
	if !testing.expect(t, err == .None) { return }
	defer rifle.schema_destroy(schema)
	testing.expect(t, schema.record_size == 8)
	testing.expect(t, len(schema.fields) == 1)
	testing.expect(t, schema.fields[0].name == "x")
	testing.expect(t, schema.fields[0].type == .U64)
	testing.expect(t, schema.fields[0].offset == 0)
	testing.expect(t, schema.fields[0].size == 8)
	encoded, encode_err := rifle.schema_encode(schema)
	defer delete(encoded)
	testing.expect(t, encode_err == .None)
	testing.expect(t, string(encoded) == string(data[:]))
	data[24] = 'y'
	testing.expect(t, schema.fields[0].name == "x")

	for end in 0 ..< len(data) {
		partial, partial_err := rifle.schema_decode(data[:end])
		defer rifle.schema_destroy(partial)
		testing.expect(t, partial_err == .Truncated)
	}
	// Reject hostile counts before attempting an allocation.
	copy(data[8:16], []u8{255, 255, 255, 255, 255, 255, 255, 127})
	_, count_err := rifle.schema_decode(data[:])
	testing.expect(t, count_err == .Truncated)
	copy(data[8:16], []u8{1, 0, 0, 0, 0, 0, 0, 0})
	copy(data[16:24], []u8{255, 255, 255, 255, 255, 255, 255, 255})
	_, name_err := rifle.schema_decode(data[:])
	testing.expect(t, name_err == .InvalidName)
}

@(test)
schema_preserves_i64_fields :: proc(t: ^testing.T) {
	fields := []rifle.SchemaField{
		{name = "large", type = .Bytes, offset = 1 << 33, size = 1 << 34},
		{name = "last", type = .I8, offset = (1 << 33) + (1 << 34), size = 1},
	}
	original := rifle.RecordSchema{record_size = 1 << 35, fields = fields}
	data, err := rifle.schema_encode(original)
	if !testing.expect(t, err == .None) { return }
	defer delete(data)
	schema, decode_err := rifle.schema_decode(data)
	if !testing.expect(t, decode_err == .None) { return }
	defer rifle.schema_destroy(schema)
	testing.expect(t, schema.record_size == original.record_size)
	for field, i in schema.fields {
		testing.expect(t, field == fields[i])
	}
}
