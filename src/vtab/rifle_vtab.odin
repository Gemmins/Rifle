package vtab

import "base:runtime"
import "core:strings"
import "core:sys/linux"
import "rifle:rifle"
import sqlite "rifle:vendor/sqlite_ext"

Vtab :: struct {
	using _:   sqlite.Vtab,
	log_data:  rifle.BaseFileData,
	log_path:  cstring,
	base_file: linux.Fd,
}

// Move to a union here once more index types introduced
Cursor :: struct {
	using _:      sqlite.Vtab_Cursor,
	record_index: i64,
	current_page: Page,
	files:        map[i64]linux.Fd,
	min_index:    i64,
	max_index:    i64,
	direction:    i8,
}

Page :: struct {
	index: i64,
	data:  []u8,
}

// Even for asc odd for desc
IndexType :: enum i32 {
	ROWID_RANGE_ASC = 0,
	ROWID_RANGE_DSC = 1,
}

PAGE_SIZE :: 1 << 13

connect :: proc "c" (db: ^sqlite.Connection, pAux: rawptr, argc: i32, argv: [^]cstring, ppVTab: ^^sqlite.Vtab, _: ^cstring) -> i32 {
	context = runtime.default_context()

	if argc < 4 {
		return sqlite.ERROR
	}

	path := argv[3]

	file_data, file_err := rifle.read_base_file(path) // Change to open and keep descriptor in table
	if file_err != nil {
		return sqlite.ERROR
	}

	pVtab, err := new(Vtab)
	if err != nil {
		return sqlite.ERROR
	}
	ppVTab^ = pVtab

	pVtab.log_data = file_data
	pVtab.log_path = strings.clone_to_cstring(string(path))

	create_string, schema_err := create_table_sql(file_data.schema)
	if schema_err != nil {
		return sqlite.ERROR
	}
	defer delete(create_string, context.allocator)

	res := sqlite.declare_vtab(db, create_string)
	if res == sqlite.Result_Code.OK {
		res = sqlite.vtab_config(db, sqlite.VTAB_DIRECTONLY)
	}
	return cast(i32)res
}

best_index :: proc "c" (pVTab: ^sqlite.Vtab, index_info: ^sqlite.Index_Info) -> i32 {
	context = runtime.default_context()
	vtab := cast(^Vtab)pVTab

	idxStr := (cast([^]u8)sqlite.malloc(index_info.nConstraint + 1))[:index_info.nConstraint + 1]
	if raw_data(idxStr) == nil {
		return sqlite.NOMEM
	}
	index_info.idxStr = cstring(raw_data(idxStr))
	index_info.needToFreeIdxStr = 1

	total_rows := vtab.log_data.head - vtab.log_data.tail
	is_rowid := false
	upper := false
	lower := false
	constraints: i32 = 0

	loop: for constraint, i in index_info.aConstraint[:index_info.nConstraint] {
		if constraint.usable == 0 || constraint.iColumn != -1 { 	// Only rowid for now
			continue
		}
		is_rowid = true
		switch constraint.op {
		case sqlite.INDEX_CONSTRAINT_EQ:
			total_rows = 1
			index_info.aConstraintUsage[i] = sqlite.Index_Constraint_Usage{constraints + 1, 0}
			idxStr[constraints] = constraint.op
			constraints += 1
			index_info.idxFlags |= sqlite.INDEX_SCAN_UNIQUE
			break loop
		case sqlite.INDEX_CONSTRAINT_GE, sqlite.INDEX_CONSTRAINT_GT:
			if !lower {
				total_rows /= 2
				lower = true
			}
			index_info.aConstraintUsage[i] = sqlite.Index_Constraint_Usage{constraints + 1, 0}
			idxStr[constraints] = constraint.op
			constraints += 1
		case sqlite.INDEX_CONSTRAINT_LE, sqlite.INDEX_CONSTRAINT_LT:
			if !upper {
				total_rows /= 2
				upper = true
			}
			index_info.aConstraintUsage[i] = sqlite.Index_Constraint_Usage{constraints + 1, 0}
			idxStr[constraints] = constraint.op
			constraints += 1
		case sqlite.INDEX_CONSTRAINT_NE:
			total_rows -= 1
			index_info.aConstraintUsage[i] = sqlite.Index_Constraint_Usage{constraints + 1, 0}
			idxStr[constraints] = constraint.op
			constraints += 1
		case:
		}
	}
	// should maybe guard fields on sqlite version
	index_info.estimatedRows = total_rows
	index_info.estimatedCost = cast(f64)((total_rows * vtab.log_data.record_size) / PAGE_SIZE)
	if is_rowid {
		index_info.idxNum = (cast(i32)IndexType.ROWID_RANGE_ASC)
	}
	if index_info.nOrderBy == 1 && index_info.aOrderBy[0].iColumn == -1 {
		index_info.orderByConsumed = 1
		index_info.idxNum += cast(i32)index_info.aOrderBy[0].desc
	}
	idxStr[constraints] = 0

	return 0
}

disconnect :: proc "c" (pVTab: ^sqlite.Vtab) -> i32 {
	context = runtime.default_context()
	vtab := cast(^Vtab)pVTab

	delete(vtab.log_path)
	rifle.schema_destroy(vtab.log_data.schema)

	err := free(vtab)
	if err != nil {
		return sqlite.ERROR
	}
	return sqlite.OK
}

open :: proc "c" (pVTab: ^sqlite.Vtab, ppCursor: ^^sqlite.Vtab_Cursor) -> i32 {
	context = runtime.default_context()
	cursor, err := new(Cursor)
	if err != nil {
		return sqlite.ERROR
	}

	cursor.pVtab = pVTab
	cursor.current_page.index = -1
	cursor.current_page.data = make_aligned([]u8, PAGE_SIZE, 1 << 12) //TODO: configure
	cursor.files = make(map[i64]linux.Fd)

	ppCursor^ = cursor
	return sqlite.OK
}

close :: proc "c" (pCursor: ^sqlite.Vtab_Cursor) -> i32 {
	context = runtime.default_context()
	cursor := cast(^Cursor)pCursor

	delete(cursor.current_page.data)
	for _, f in cursor.files {
		linux.close(f)
	}
	delete(cursor.files)

	err := free(cursor)
	if err != nil {
		return sqlite.ERROR
	}
	return sqlite.OK
}

filter :: proc "c" (pCursor: ^sqlite.Vtab_Cursor, idxNum: i32, idxStr: cstring, argc: i32, argv: [^]^sqlite.Value) -> i32 {
	context = runtime.default_context()
	cursor := cast(^Cursor)pCursor
	vtab := cast(^Vtab)cursor.pVtab
	idxOps := cast([^]u8)idxStr

	// Should do a re-read of the base file atp
	cursor.min_index = vtab.log_data.tail
	cursor.max_index = vtab.log_data.head
	cursor.direction = bool(idxNum & 1) ? -1 : 1

	if argc != 0 {
		switch cast(IndexType)idxNum {
		case .ROWID_RANGE_ASC, .ROWID_RANGE_DSC:
			for constraint_value, i in argv[:argc] {
				constraint_value := sqlite.value_int64(constraint_value)
				op := idxOps[i]
				switch op {
				case sqlite.INDEX_CONSTRAINT_EQ:
					cursor.max_index = constraint_value + 1
					cursor.min_index = constraint_value
				case sqlite.INDEX_CONSTRAINT_GT:
					if cursor.min_index < constraint_value + 1 {
						cursor.min_index = constraint_value + 1
					}
				case sqlite.INDEX_CONSTRAINT_GE:
					if cursor.min_index < constraint_value {
						cursor.min_index = constraint_value
					}
				case sqlite.INDEX_CONSTRAINT_LT:
					if cursor.max_index > constraint_value {
						cursor.max_index = constraint_value
					}
				case sqlite.INDEX_CONSTRAINT_LE:
					if cursor.max_index > constraint_value + 1 {
						cursor.max_index = constraint_value + 1
					}
				}
			}
		case: // For when more are added
		}
	}


	// Currently return errror if cant open file (may have been dropped)
	// Should change this to re-calculating min based off of which files we managed to open
	cursor.record_index = cursor.direction < 1 ? cursor.max_index - 1 : cursor.min_index
	return open_files(cursor, cursor.min_index, cursor.max_index)
}

next :: proc "c" (pCursor: ^sqlite.Vtab_Cursor) -> i32 {
	cursor := cast(^Cursor)pCursor
	cursor.record_index += cast(i64)cursor.direction
	return sqlite.OK
}

eof :: proc "c" (pCursor: ^sqlite.Vtab_Cursor) -> i32 {
	cursor := cast(^Cursor)pCursor
	if cursor.record_index >= cursor.max_index || cursor.record_index < cursor.min_index {
		return 1
	}
	return 0
}

column :: proc "c" (pCursor: ^sqlite.Vtab_Cursor, pContext: ^sqlite.Context, N: i32) -> i32 {
	cursor := cast(^Cursor)pCursor
	vtab := cast(^Vtab)cursor.pVtab
	field := vtab.log_data.schema.fields[N]

	page_size := i64(len(cursor.current_page.data))
	record_offset := cursor.record_index * vtab.log_data.record_size
	page_index := record_offset / page_size
	if cursor.current_page.index != page_index {
		if rc := read_page_at(cursor, page_index, vtab.log_data.file_size); rc != sqlite.OK {
			return rc
		}
	}

	// For now, records must fit within a single page.
	field_offset := record_offset % page_size + field.offset
	column_data := cursor.current_page.data[field_offset:][:field.size]
	// possible unaligned loads here, maybe indicate as such
	switch field.type {
	case .I8:
		sqlite.result_int(pContext, i32((cast(^i8)raw_data(column_data))^))
	case .I16:
		sqlite.result_int(pContext, i32((cast(^i16)raw_data(column_data))^))
	case .I32:
		sqlite.result_int(pContext, (cast(^i32)raw_data(column_data))^)
	case .I64:
		sqlite.result_int64(pContext, (cast(^i64)raw_data(column_data))^)
	case .U8:
		sqlite.result_int(pContext, i32((cast(^u8)raw_data(column_data))^))
	case .U16:
		sqlite.result_int(pContext, i32((cast(^u16)raw_data(column_data))^))
	case .U32:
		sqlite.result_int64(pContext, i64((cast(^u32)raw_data(column_data))^))
	case .U64:
		value := (cast(^u64)raw_data(column_data))^
		// SQLite INTEGER values are signed 64-bit integers.
		if value > u64(max(i64)) {
			sqlite.result_error(pContext, "U64 value exceeds SQLite INTEGER range", -1)
			return sqlite.ERROR
		}
		sqlite.result_int64(pContext, i64(value))
	case .F32:
		sqlite.result_double(pContext, f64((cast(^f32)raw_data(column_data))^))
	case .F64:
		sqlite.result_double(pContext, (cast(^f64)raw_data(column_data))^)
	case .Bool:
		sqlite.result_int(pContext, i32((cast(^u8)raw_data(column_data))^ != 0))
	case .Bytes:
		sqlite.result_blob64(pContext, raw_data(column_data), u64(len(column_data)), sqlite.TRANSIENT)
	case .Text:
		// Look at slicing for nul termination
		sqlite.result_text64(pContext, cast(cstring)raw_data(column_data), u64(len(column_data)), sqlite.TRANSIENT, sqlite.UTF8)
	case .Invalid:
		sqlite.result_error(pContext, "Invalid field type", -1)
		return sqlite.ERROR
	}

	return sqlite.OK
}

rowid :: proc "c" (pCursor: ^sqlite.Vtab_Cursor, pRowid: ^i64) -> i32 {
	cursor := cast(^Cursor)pCursor
	pRowid^ = cursor.record_index
	return 0
}

rename :: proc "c" (pVtab: ^Vtab, zNew: cstring) -> i32 {
	return sqlite.OK
}

rifleModule := sqlite.Module {
	xCreate     = connect,
	xConnect    = connect,
	xBestIndex  = best_index,
	xDisconnect = disconnect,
	xOpen       = open,
	xClose      = close,
	xFilter     = filter,
	xNext       = next,
	xEof        = eof,
	xColumn     = column,
	xRowid      = rowid,
	xDestroy    = disconnect,
	xRename     = rename,
}

@(export)
sqlite3_riflevtab_init :: proc "c" (db: ^sqlite.Connection, pzErrMsg: ^cstring, api_routines: ^sqlite.Api_Routines) -> sqlite.Result_Code {
	rc := sqlite.Result_Code.OK
	if !sqlite.init_api(api_routines) {
		return .ERROR
	}
	rc = sqlite.create_module(db, "rifle", &rifleModule, nil)
	return rc
}
