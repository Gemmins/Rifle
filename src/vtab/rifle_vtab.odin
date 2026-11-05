package vtab

// import "base:runtime"
// import "core:strings"
// import "core:os"
import sqlite "rifle:vendor/sqlite_ext"

sqlite3_api: ^sqlite.Api_Routines = nil

create :: proc "c" (_: ^sqlite.Connection, pAux: rawptr, argc: i32, argv: [^]cstring, ppVTab: ^^sqlite.Vtab, _: ^cstring) -> i32 {

	return 0
}

connect :: proc "c" (_: ^sqlite.Connection, pAux: rawptr, argc: i32, argv: [^]cstring, ppVTab: ^^sqlite.Vtab, _: ^cstring) -> i32 {
	return 0
}

best_index :: proc "c" (pVTab: ^sqlite.Vtab, _: ^sqlite.Index_Info) -> i32 {
	return 0
}

disconnect :: proc "c" (pVTab: ^sqlite.Vtab) -> i32 {
	return 0
}

open :: proc "c" (pVTab: ^sqlite.Vtab, ppCursor: ^^sqlite.Vtab_Cursor) -> i32 {
	return 0
}

close :: proc "c" (_: ^sqlite.Vtab_Cursor) -> i32 {
	return 0
}

filter :: proc "c" (_: ^sqlite.Vtab_Cursor, idxNum: i32, idxStr: cstring, argc: i32, argv: [^]^sqlite.Value) -> i32 {
	return 0
}

next :: proc "c" (_: ^sqlite.Vtab_Cursor) -> i32 {
	return 0
}

eof :: proc "c" (_: ^sqlite.Vtab_Cursor) -> i32 {
	return 0
}

column :: proc "c" (_: ^sqlite.Vtab_Cursor, _: ^sqlite.Context, _: i32) -> i32 {
	return 0
}

rowid :: proc "c" (_: ^sqlite.Vtab_Cursor, pRowid: ^i64) -> i32 {
	return 0
}

rifleModule := sqlite.Module {
	xCreate     = create,
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
}

@(export)
sqlite3_riflevtab_init :: proc "c" (db: ^sqlite.Connection, pzErrMsg: ^cstring, api_routines: ^sqlite.Api_Routines) -> sqlite.Result_Code {
	rc := sqlite.Result_Code.OK
	if !sqlite.init_api(api_routines) {return .ERROR}
	rc = sqlite.create_module(db, "rifle", &rifleModule, nil)
	return rc
}
