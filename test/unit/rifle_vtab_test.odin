package unit

import "core:testing"
import sqlite "rifle:vendor/sqlite_ext"
import vtab "rifle:vtab"

@(test)
given_cursor_bounds_when_advanced_then_eof_changes_only_after_the_inclusive_maximum :: proc(t: ^testing.T) {
	// Arrange
	cursor := vtab.Cursor{record_index = 4, min_index = 4, max_index = 6}
	sqlite_cursor := cast(^sqlite.Vtab_Cursor)&cursor

	// Act
	initial := vtab.eof(sqlite_cursor)
	first_next := vtab.next(sqlite_cursor)
	middle := vtab.eof(sqlite_cursor)
	second_next := vtab.next(sqlite_cursor)
	at_maximum := vtab.eof(sqlite_cursor)
	third_next := vtab.next(sqlite_cursor)
	after_maximum := vtab.eof(sqlite_cursor)
	cursor.record_index = 3
	before_minimum := vtab.eof(sqlite_cursor)

	// Assert
	testing.expect_value(t, initial, i32(0))
	testing.expect_value(t, first_next, i32(sqlite.OK))
	testing.expect_value(t, middle, i32(0))
	testing.expect_value(t, second_next, i32(sqlite.OK))
	testing.expect_value(t, at_maximum, i32(0))
	testing.expect_value(t, third_next, i32(sqlite.OK))
	testing.expect_value(t, after_maximum, i32(1))
	testing.expect_value(t, before_minimum, i32(1))
}

@(test)
given_cursor_record_index_when_rowid_is_requested_then_record_index_is_returned :: proc(t: ^testing.T) {
	// Arrange
	cursor := vtab.Cursor{record_index = 41}
	sqlite_cursor := cast(^sqlite.Vtab_Cursor)&cursor
	row_id: i64

	// Act
	err := vtab.rowid(sqlite_cursor, &row_id)

	// Assert
	testing.expect_value(t, err, i32(sqlite.OK))
	testing.expect_value(t, row_id, i64(41))
}
