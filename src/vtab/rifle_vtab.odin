package vtab

import "base:runtime"
import "rifle:rifle"
import sqlite "rifle:vendor/sqlite_ext"

Vtab :: struct {
	using _:   sqlite.Vtab,
	file_data: rifle.BaseFileData,
}

Cursor :: struct {
	using _:      ^sqlite.Vtab_Cursor,
	record_index: i64,
	files:        []i32,
	min_index:    i64,
	max_index:    i64,
}

connect :: proc "c" (db: ^sqlite.Connection, pAux: rawptr, argc: i32, argv: [^]cstring, ppVTab: ^^sqlite.Vtab, _: ^cstring) -> i32 {
	context = runtime.default_context()

	if argc < 4 {
		return sqlite.ERROR
	}

	file_data, file_err := rifle.read_base_file(argv[3])
	if file_err != nil {
		return sqlite.ERROR
	}

	pVtab, err := new(Vtab)
	if err != nil {
		return sqlite.ERROR
	}
	ppVTab^ = pVtab

	pVtab.file_data = file_data

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

best_index :: proc "c" (pVTab: ^sqlite.Vtab, _: ^sqlite.Index_Info) -> i32 {
	return 0
}

disconnect :: proc "c" (pVTab: ^sqlite.Vtab) -> i32 {
	context = runtime.default_context()
	err := free(pVTab)
	if err != nil {
		return sqlite.ERROR
	}
	return sqlite.OK
}

open :: proc "c" (pVTab: ^sqlite.Vtab, ppCursor: ^^sqlite.Vtab_Cursor) -> i32 {
	context = runtime.default_context()
	pc, err := new(Cursor)
	if err != nil {
		return sqlite.ERROR
	}
	ppCursor^ = pc
	return sqlite.OK
}

close :: proc "c" (pCursor: ^sqlite.Vtab_Cursor) -> i32 {
	context = runtime.default_context()
	err := free(pCursor)
	if err != nil {
		return sqlite.ERROR
	}
	return sqlite.OK
}

filter :: proc "c" (pCursor: ^sqlite.Vtab_Cursor, idxNum: i32, idxStr: cstring, argc: i32, argv: [^]^sqlite.Value) -> i32 {
	return 0
}

next :: proc "c" (pCursor: ^sqlite.Vtab_Cursor) -> i32 {
	cursor := cast(^Cursor)pCursor
	cursor.record_index += 1
	return 1
}

eof :: proc "c" (pCursor: ^sqlite.Vtab_Cursor) -> i32 {
	cursor := cast(^Cursor)pCursor
	if cursor.record_index > cursor.max_index || cursor.record_index < cursor.min_index {
		return 0
	}
	return 1
}

column :: proc "c" (pCursor: ^sqlite.Vtab_Cursor, pContext: ^sqlite.Context, N: i32) -> i32 {
	cursor := cast(^Cursor)pCursor
	vtab := cast(^Vtab)cursor.pVtab
	field := vtab.file_data.schema.fields[N]


	switch field.type {
	case .I8, .I16, .I32:
		sqlite.result_int(pContext, 10)
		return sqlite.OK
	case .I64:
		sqlite.result_int64(pContext, 10)
		return sqlite.OK
	case .
	}


	return 0
}

rowid :: proc "c" (pCursor: ^sqlite.Vtab_Cursor, pRowid: ^i64) -> i32 {
	cursor := cast(^Cursor)pCursor
	pRowid^ = cursor.record_index
	return 0
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
}

@(export)
sqlite3_riflevtab_init :: proc "c" (db: ^sqlite.Connection, pzErrMsg: ^cstring, api_routines: ^sqlite.Api_Routines) -> sqlite.Result_Code {
	rc := sqlite.Result_Code.OK
	if !sqlite.init_api(api_routines) {return .ERROR}
	rc = sqlite.create_module(db, "rifle", &rifleModule, nil)
	return rc
}
