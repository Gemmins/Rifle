/*
** 2001-09-15
**
** The author disclaims copyright to this source code.  In place of
** a legal notice, here is a blessing:
**
**    May you do good and not evil.
**    May you find forgiveness for yourself and forgive others.
**    May you share freely, never taking more than you give.
**
*************************************************************************
** This header file defines the interface that the SQLite library
** presents to client programs.  If a C-function, structure, datatype,
** or constant definition does not appear in this file, then it is
** not a published API of SQLite, is subject to change without
** notice, and should not be referenced by programs that use SQLite.
**
** Some of the definitions that are in this file are marked as
** "experimental".  Experimental interfaces are normally new
** features recently added to SQLite.  We do not anticipate changes
** to experimental interfaces but reserve the right to make minor changes
** if experience from use "in the wild" suggest such changes are prudent.
**
** The official C-language API documentation for SQLite is derived
** from comments in this file.  This file is the authoritative source
** on how SQLite interfaces are supposed to operate.
**
** The name of this file under configuration management is "sqlite.h.in".
** The makefile makes some minor changes to this file (such as inserting
** the version number) and changes its name to "sqlite3.h" as
** part of the build process.
*/
package sqlite_ext


/*
** CAPI3REF: Compile-Time Library Version Numbers
**
** ^(The [SQLITE_VERSION] C preprocessor macro in the sqlite3.h header
** evaluates to a string literal that is the SQLite version in the
** format "X.Y.Z" where X is the major version number (always 3 for
** SQLite3) and Y is the minor version number and Z is the release number.)^
** ^(The [SQLITE_VERSION_NUMBER] C preprocessor macro resolves to an integer
** with the value (X*1000000 + Y*1000 + Z) where X, Y, and Z are the same
** numbers used in [SQLITE_VERSION].)^
** The SQLITE_VERSION_NUMBER for any given release of SQLite will also
** be larger than the release from which it is derived.  Either Y will
** be held constant and Z will be incremented or else Y will be incremented
** and Z will be reset to zero.
**
** Since [version 3.6.18] ([dateof:3.6.18]),
** SQLite source code has been stored in the
** <a href="http://fossil-scm.org/">Fossil configuration management
** system</a>.  ^The SQLITE_SOURCE_ID macro evaluates to
** a string which identifies a particular check-in of SQLite
** within its configuration management system.  ^The SQLITE_SOURCE_ID
** string contains the date and time of the check-in (UTC) and a SHA1
** or SHA3-256 hash of the entire source tree.  If the source code has
** been edited in any way since it was last checked in, then the last
** four hexadecimal digits of the hash may be modified.
**
** See also: [sqlite3_libversion()],
** [sqlite3_libversion_number()], [sqlite3_sourceid()],
** [sqlite_version()] and [sqlite_source_id()].
*/
VERSION :: "3.54.1"
VERSION_NUMBER :: 3054001
SOURCE_ID :: "2026-10-16 14:45:20 555e07ef33f69a0957d24d8e555b702464a131d6f1607f4c3c1e4551e8e6ca76"
SCM_BRANCH :: "branch-3.54"
SCM_TAGS :: "release version-3.54.1"
SCM_DATETIME :: "2026-10-16T14:45:20.546Z"


Connection :: struct {}


/*
** The type for a callback function.
** This is legacy and deprecated.  It is included for historical
** compatibility and is not documented.
*/
Callback :: proc "c" (_: rawptr, _: i32, _: ^cstring, _: ^cstring) -> i32


/*
** CAPI3REF: Result Codes
** KEYWORDS: {result code definitions}
**
** Many SQLite functions return an integer result code from the set shown
** here in order to indicate success or failure.
**
** New error codes may be added in future versions of SQLite.
**
** See also: [extended result code definitions]
*/
OK :: 0 /* Successful result */

/* beginning-of-error-codes */
ERROR :: 1 /* Generic error */
INTERNAL :: 2 /* Internal logic error in SQLite */
PERM :: 3 /* Access permission denied */
ABORT :: 4 /* Callback routine requested an abort */
BUSY :: 5 /* The database file is locked */
LOCKED :: 6 /* A table in the database is locked */
NOMEM :: 7 /* A malloc() failed */
READONLY :: 8 /* Attempt to write a readonly database */
INTERRUPT :: 9 /* Operation terminated by sqlite3_interrupt()*/
IOERR :: 10 /* Some kind of disk I/O error occurred */
CORRUPT :: 11 /* The database disk image is malformed */
NOTFOUND :: 12 /* Unknown opcode in sqlite3_file_control() */
FULL :: 13 /* Insertion failed because database is full */
CANTOPEN :: 14 /* Unable to open the database file */
PROTOCOL :: 15 /* Database lock protocol error */
EMPTY :: 16 /* No content */
SCHEMA :: 17 /* The database schema changed */
TOOBIG :: 18 /* String or BLOB exceeds size limit */
CONSTRAINT :: 19 /* Abort due to constraint violation */
MISMATCH :: 20 /* Data type mismatch */
MISUSE :: 21 /* Library used incorrectly */
NOLFS :: 22 /* Uses OS features not supported on host */
AUTH :: 23 /* Authorization denied */
FORMAT :: 24 /* Not used */
RANGE :: 25 /* 2nd parameter to sqlite3_bind out of range */
NOTADB :: 26 /* File opened that is not a database file */
NOTICE :: 27 /* Notifications from sqlite3_log() */
WARNING :: 28 /* Warnings from sqlite3_log() */
ROW :: 100 /* sqlite3_step() has another row ready */
DONE :: 101 /* sqlite3_step() has finished executing */

/* end-of-error-codes */

/*
** CAPI3REF: Extended Result Codes
** KEYWORDS: {extended result code definitions}
**
** In its default configuration, SQLite API routines return one of 30 integer
** [result codes].  However, experience has shown that many of
** these result codes are too coarse-grained.  They do not provide as
** much information about problems as programmers might like.  In an effort to
** address this, newer versions of SQLite (version 3.3.8 [dateof:3.3.8]
** and later) include
** support for additional result codes that provide more detailed information
** about errors. These [extended result codes] are enabled or disabled
** on a per database connection basis using the
** [sqlite3_extended_result_codes()] API.  Or, the extended code for
** the most recent error can be obtained using
** [sqlite3_extended_errcode()].
*/
ERROR_MISSING_COLLSEQ :: (ERROR | (1 << 8))
ERROR_RETRY :: (ERROR | (2 << 8))
ERROR_SNAPSHOT :: (ERROR | (3 << 8))
ERROR_RESERVESIZE :: (ERROR | (4 << 8))
ERROR_KEY :: (ERROR | (5 << 8))
ERROR_UNABLE :: (ERROR | (6 << 8))
IOERR_READ :: (IOERR | (1 << 8))
IOERR_SHORT_READ :: (IOERR | (2 << 8))
IOERR_WRITE :: (IOERR | (3 << 8))
IOERR_FSYNC :: (IOERR | (4 << 8))
IOERR_DIR_FSYNC :: (IOERR | (5 << 8))
IOERR_TRUNCATE :: (IOERR | (6 << 8))
IOERR_FSTAT :: (IOERR | (7 << 8))
IOERR_UNLOCK :: (IOERR | (8 << 8))
IOERR_RDLOCK :: (IOERR | (9 << 8))
IOERR_DELETE :: (IOERR | (10 << 8))
IOERR_BLOCKED :: (IOERR | (11 << 8))
IOERR_NOMEM :: (IOERR | (12 << 8))
IOERR_ACCESS :: (IOERR | (13 << 8))
IOERR_CHECKRESERVEDLOCK :: (IOERR | (14 << 8))
IOERR_LOCK :: (IOERR | (15 << 8))
IOERR_CLOSE :: (IOERR | (16 << 8))
IOERR_DIR_CLOSE :: (IOERR | (17 << 8))
IOERR_SHMOPEN :: (IOERR | (18 << 8))
IOERR_SHMSIZE :: (IOERR | (19 << 8))
IOERR_SHMLOCK :: (IOERR | (20 << 8))
IOERR_SHMMAP :: (IOERR | (21 << 8))
IOERR_SEEK :: (IOERR | (22 << 8))
IOERR_DELETE_NOENT :: (IOERR | (23 << 8))
IOERR_MMAP :: (IOERR | (24 << 8))
IOERR_GETTEMPPATH :: (IOERR | (25 << 8))
IOERR_CONVPATH :: (IOERR | (26 << 8))
IOERR_VNODE :: (IOERR | (27 << 8))
IOERR_AUTH :: (IOERR | (28 << 8))
IOERR_BEGIN_ATOMIC :: (IOERR | (29 << 8))
IOERR_COMMIT_ATOMIC :: (IOERR | (30 << 8))
IOERR_ROLLBACK_ATOMIC :: (IOERR | (31 << 8))
IOERR_DATA :: (IOERR | (32 << 8))
IOERR_CORRUPTFS :: (IOERR | (33 << 8))
IOERR_IN_PAGE :: (IOERR | (34 << 8))
IOERR_BADKEY :: (IOERR | (35 << 8))
IOERR_CODEC :: (IOERR | (36 << 8))
LOCKED_SHAREDCACHE :: (LOCKED | (1 << 8))
LOCKED_VTAB :: (LOCKED | (2 << 8))
BUSY_RECOVERY :: (BUSY | (1 << 8))
BUSY_SNAPSHOT :: (BUSY | (2 << 8))
BUSY_TIMEOUT :: (BUSY | (3 << 8))
CANTOPEN_NOTEMPDIR :: (CANTOPEN | (1 << 8))
CANTOPEN_ISDIR :: (CANTOPEN | (2 << 8))
CANTOPEN_FULLPATH :: (CANTOPEN | (3 << 8))
CANTOPEN_CONVPATH :: (CANTOPEN | (4 << 8))
CANTOPEN_DIRTYWAL :: (CANTOPEN | (5 << 8)) /* Not Used */
CANTOPEN_SYMLINK :: (CANTOPEN | (6 << 8))
CORRUPT_VTAB :: (CORRUPT | (1 << 8))
CORRUPT_SEQUENCE :: (CORRUPT | (2 << 8))
CORRUPT_INDEX :: (CORRUPT | (3 << 8))
READONLY_RECOVERY :: (READONLY | (1 << 8))
READONLY_CANTLOCK :: (READONLY | (2 << 8))
READONLY_ROLLBACK :: (READONLY | (3 << 8))
READONLY_DBMOVED :: (READONLY | (4 << 8))
READONLY_CANTINIT :: (READONLY | (5 << 8))
READONLY_DIRECTORY :: (READONLY | (6 << 8))
ABORT_ROLLBACK :: (ABORT | (2 << 8))
CONSTRAINT_CHECK :: (CONSTRAINT | (1 << 8))
CONSTRAINT_COMMITHOOK :: (CONSTRAINT | (2 << 8))
CONSTRAINT_FOREIGNKEY :: (CONSTRAINT | (3 << 8))
CONSTRAINT_FUNCTION :: (CONSTRAINT | (4 << 8))
CONSTRAINT_NOTNULL :: (CONSTRAINT | (5 << 8))
CONSTRAINT_PRIMARYKEY :: (CONSTRAINT | (6 << 8))
CONSTRAINT_TRIGGER :: (CONSTRAINT | (7 << 8))
CONSTRAINT_UNIQUE :: (CONSTRAINT | (8 << 8))
CONSTRAINT_VTAB :: (CONSTRAINT | (9 << 8))
CONSTRAINT_ROWID :: (CONSTRAINT | (10 << 8))
CONSTRAINT_PINNED :: (CONSTRAINT | (11 << 8))
CONSTRAINT_DATATYPE :: (CONSTRAINT | (12 << 8))
NOTICE_RECOVER_WAL :: (NOTICE | (1 << 8))
NOTICE_RECOVER_ROLLBACK :: (NOTICE | (2 << 8))
NOTICE_RBU :: (NOTICE | (3 << 8))
WARNING_AUTOINDEX :: (WARNING | (1 << 8))
AUTH_USER :: (AUTH | (1 << 8))
OK_LOAD_PERMANENTLY :: (OK | (1 << 8))
OK_SYMLINK :: (OK | (2 << 8)) /* internal only */

Open_Flag :: enum i32 {
	/*
	** CAPI3REF: Flags For File Open Operations
	**
	** These bit values are intended for use in the
	** 3rd parameter to the [sqlite3_open_v2()] interface and
	** in the 4th parameter to the [sqlite3_vfs.xOpen] method.
	**
	** Only those flags marked as "Ok for sqlite3_open_v2()" may be
	** used as the third argument to the [sqlite3_open_v2()] interface.
	** The other flags have historically been ignored by sqlite3_open_v2(),
	** though future versions of SQLite might change so that an error is
	** raised if any of the disallowed bits are passed into sqlite3_open_v2().
	** Applications should not depend on the historical behavior.
	**
	** Note in particular that passing the SQLITE_OPEN_EXCLUSIVE flag into
	** [sqlite3_open_v2()] does *not* cause the underlying database file
	** to be opened using O_EXCL.  Passing SQLITE_OPEN_EXCLUSIVE into
	** [sqlite3_open_v2()] has historically been a no-op and might become an
	** error in future versions of SQLite.
	*/
	READONLY       = 0, /* Ok for sqlite3_open_v2() */
	READWRITE      = 1, /* Ok for sqlite3_open_v2() */
	CREATE         = 2, /* Ok for sqlite3_open_v2() */
	DELETEONCLOSE  = 3, /* VFS only */
	EXCLUSIVE      = 4, /* VFS only */
	AUTOPROXY      = 5, /* VFS only */
	URI            = 6, /* Ok for sqlite3_open_v2() */
	MEMORY         = 7, /* Ok for sqlite3_open_v2() */
	MAIN_DB        = 8, /* VFS only */
	TEMP_DB        = 9, /* VFS only */
	TRANSIENT_DB   = 10, /* VFS only */
	MAIN_JOURNAL   = 11, /* VFS only */
	TEMP_JOURNAL   = 12, /* VFS only */
	SUBJOURNAL     = 13, /* VFS only */
	SUPER_JOURNAL  = 14, /* VFS only */
	NOMUTEX        = 15, /* Ok for sqlite3_open_v2() */
	FULLMUTEX      = 16, /* Ok for sqlite3_open_v2() */
	SHAREDCACHE    = 17, /* Ok for sqlite3_open_v2() */
	PRIVATECACHE   = 18, /* Ok for sqlite3_open_v2() */
	WAL            = 19, /* VFS only */
	NOFOLLOW       = 24, /* Ok for sqlite3_open_v2() */
	EXRESCODE      = 25, /* Extended result codes */

	/* Reserved:                         0x00F00000 */
	/* Legacy compatibility: */
	MASTER_JOURNAL = 14, /* VFS only */
}

Open_Flags :: bit_set[Open_Flag;i32]

/*
** CAPI3REF: Device Characteristics
**
** The xDeviceCharacteristics method of the [sqlite3_io_methods]
** object returns an integer which is a vector of these
** bit values expressing I/O characteristics of the mass storage
** device that holds the file that the [sqlite3_io_methods]
** refers to.
**
** The SQLITE_IOCAP_ATOMIC property means that all writes of
** any size are atomic.  The SQLITE_IOCAP_ATOMICnnn values
** mean that writes of blocks that are nnn bytes in size and
** are aligned to an address which is an integer multiple of
** nnn are atomic.  The SQLITE_IOCAP_SAFE_APPEND value means
** that when data is appended to a file, the data is appended
** first then the size of the file is extended, never the other
** way around.  The SQLITE_IOCAP_SEQUENTIAL property means that
** information is written to disk in the same order as calls
** to xWrite().  The SQLITE_IOCAP_POWERSAFE_OVERWRITE property means that
** after reboot following a crash or power loss, the only bytes in a
** file that were written at the application level might have changed
** and that adjacent bytes, even bytes within the same sector are
** guaranteed to be unchanged.  The SQLITE_IOCAP_UNDELETABLE_WHEN_OPEN
** flag indicates that a file cannot be deleted when open.  The
** SQLITE_IOCAP_IMMUTABLE flag indicates that the file is on
** read-only media and cannot be changed even by processes with
** elevated privileges.
**
** The SQLITE_IOCAP_BATCH_ATOMIC property means that the underlying
** filesystem supports doing multiple write operations atomically when those
** write operations are bracketed by [SQLITE_FCNTL_BEGIN_ATOMIC_WRITE] and
** [SQLITE_FCNTL_COMMIT_ATOMIC_WRITE].
**
** The SQLITE_IOCAP_SUBPAGE_READ property means that it is ok to read
** from the database file in amounts that are not a multiple of the
** page size and that do not begin at a page boundary.  Without this
** property, SQLite is careful to only do full-page reads and write
** on aligned pages, with the one exception that it will do a sub-page
** read of the first page to access the database header.
*/
IOCAP_ATOMIC :: 0x00000001
IOCAP_ATOMIC512 :: 0x00000002
IOCAP_ATOMIC1K :: 0x00000004
IOCAP_ATOMIC2K :: 0x00000008
IOCAP_ATOMIC4K :: 0x00000010
IOCAP_ATOMIC8K :: 0x00000020
IOCAP_ATOMIC16K :: 0x00000040
IOCAP_ATOMIC32K :: 0x00000080
IOCAP_ATOMIC64K :: 0x00000100
IOCAP_SAFE_APPEND :: 0x00000200
IOCAP_SEQUENTIAL :: 0x00000400
IOCAP_UNDELETABLE_WHEN_OPEN :: 0x00000800
IOCAP_POWERSAFE_OVERWRITE :: 0x00001000
IOCAP_IMMUTABLE :: 0x00002000
IOCAP_BATCH_ATOMIC :: 0x00004000
IOCAP_SUBPAGE_READ :: 0x00008000

/*
** CAPI3REF: File Locking Levels
**
** SQLite uses one of these integer values as the second
** argument to calls it makes to the xLock() and xUnlock() methods
** of an [sqlite3_io_methods] object.  These values are ordered from
** least restrictive to most restrictive.
**
** The argument to xLock() is always SHARED or higher.  The argument to
** xUnlock is either SHARED or NONE.
*/
LOCK_NONE :: 0 /* xUnlock() only */
LOCK_SHARED :: 1 /* xLock() or xUnlock() */
LOCK_RESERVED :: 2 /* xLock() only */
LOCK_PENDING :: 3 /* xLock() only */
LOCK_EXCLUSIVE :: 4 /* xLock() only */

/*
** CAPI3REF: Synchronization Type Flags
**
** When SQLite invokes the xSync() method of an
** [sqlite3_io_methods] object it uses a combination of
** these integer values as the second argument.
**
** When the SQLITE_SYNC_DATAONLY flag is used, it means that the
** sync operation only needs to flush data to mass storage.  Inode
** information need not be flushed. If the lower four bits of the flag
** equal SQLITE_SYNC_NORMAL, that means to use normal fsync() semantics.
** If the lower four bits equal SQLITE_SYNC_FULL, that means
** to use Mac OS X style fullsync instead of fsync().
**
** Do not confuse the SQLITE_SYNC_NORMAL and SQLITE_SYNC_FULL flags
** with the [PRAGMA synchronous]=NORMAL and [PRAGMA synchronous]=FULL
** settings.  The [synchronous pragma] determines when calls to the
** xSync VFS method occur and applies uniformly across all platforms.
** The SQLITE_SYNC_NORMAL and SQLITE_SYNC_FULL flags determine how
** energetic or rigorous or forceful the sync operations are and
** only make a difference on Mac OSX for the default SQLite code.
** (Third-party VFS implementations might also make the distinction
** between SQLITE_SYNC_NORMAL and SQLITE_SYNC_FULL, but among the
** operating systems natively supported by SQLite, only Mac OSX
** cares about the difference.)
*/
SYNC_NORMAL :: 0x00002
SYNC_FULL :: 0x00003
SYNC_DATAONLY :: 0x00010

File :: struct {
	pMethods: ^Io_Methods, /* Methods for an open file */
}

Io_Methods :: struct {
	iVersion:               i32,
	xClose:                 proc "c" (_: ^File) -> i32,
	xRead:                  proc "c" (_: ^File, _: rawptr, iAmt: i32, iOfst: i64) -> i32,
	xWrite:                 proc "c" (_: ^File, _: rawptr, iAmt: i32, iOfst: i64) -> i32,
	xTruncate:              proc "c" (_: ^File, size: i64) -> i32,
	xSync:                  proc "c" (_: ^File, flags: i32) -> i32,
	xFileSize:              proc "c" (_: ^File, pSize: ^i64) -> i32,
	xLock:                  proc "c" (_: ^File, _: i32) -> i32,
	xUnlock:                proc "c" (_: ^File, _: i32) -> i32,
	xCheckReservedLock:     proc "c" (_: ^File, pResOut: ^i32) -> i32,
	xFileControl:           proc "c" (_: ^File, op: i32, pArg: rawptr) -> i32,
	xSectorSize:            proc "c" (_: ^File) -> i32,
	xDeviceCharacteristics: proc "c" (_: ^File) -> i32,

	/* Methods above are valid for version 1 */
	xShmMap:                proc "c" (_: ^File, iPg: i32, pgsz: i32, _: i32, _: ^rawptr) -> i32,
	xShmLock:               proc "c" (_: ^File, offset: i32, n: i32, flags: i32) -> i32,
	xShmBarrier:            proc "c" (_: ^File),
	xShmUnmap:              proc "c" (_: ^File, deleteFlag: i32) -> i32,

	/* Methods above are valid for version 2 */
	xFetch:                 proc "c" (_: ^File, iOfst: i64, iAmt: i32, pp: ^rawptr) -> i32,
	xUnfetch:               proc "c" (_: ^File, iOfst: i64, p: rawptr) -> i32,
}

/*
** CAPI3REF: Standard File Control Opcodes
** KEYWORDS: {file control opcodes} {file control opcode}
**
** These integer constants are opcodes for the xFileControl method
** of the [sqlite3_io_methods] object and for the [sqlite3_file_control()]
** interface.
**
** <ul>
** <li>[[SQLITE_FCNTL_LOCKSTATE]]
** The [SQLITE_FCNTL_LOCKSTATE] opcode is used for debugging.  This
** opcode causes the xFileControl method to write the current state of
** the lock (one of [SQLITE_LOCK_NONE], [SQLITE_LOCK_SHARED],
** [SQLITE_LOCK_RESERVED], [SQLITE_LOCK_PENDING], or [SQLITE_LOCK_EXCLUSIVE])
** into an integer that the pArg argument points to.
** This capability is only available if SQLite is compiled with [SQLITE_DEBUG].
**
** <li>[[SQLITE_FCNTL_SIZE_HINT]]
** The [SQLITE_FCNTL_SIZE_HINT] opcode is used by SQLite to give the VFS
** layer a hint of how large the database file will grow to be during the
** current transaction.  This hint is not guaranteed to be accurate but it
** is often close.  The underlying VFS might choose to preallocate database
** file space based on this hint in order to help writes to the database
** file run faster.
**
** <li>[[SQLITE_FCNTL_SIZE_LIMIT]]
** The [SQLITE_FCNTL_SIZE_LIMIT] opcode is used by in-memory VFS that
** implements [sqlite3_deserialize()] to set an upper bound on the size
** of the in-memory database.  The argument is a pointer to a [sqlite3_int64].
** If the integer pointed to is negative, then it is filled in with the
** current limit.  Otherwise the limit is set to the larger of the value
** of the integer pointed to and the current database size.  The integer
** pointed to is set to the new limit.
**
** <li>[[SQLITE_FCNTL_CHUNK_SIZE]]
** The [SQLITE_FCNTL_CHUNK_SIZE] opcode is used to request that the VFS
** extends and truncates the database file in chunks of a size specified
** by the user. The fourth argument to [sqlite3_file_control()] should
** point to an integer (type int) containing the new chunk-size to use
** for the nominated database. Allocating database file space in large
** chunks (say 1MB at a time), may reduce file-system fragmentation and
** improve performance on some systems.
**
** <li>[[SQLITE_FCNTL_FILE_POINTER]]
** The [SQLITE_FCNTL_FILE_POINTER] opcode is used to obtain a pointer
** to the [sqlite3_file] object associated with a particular database
** connection.  See also [SQLITE_FCNTL_JOURNAL_POINTER].
**
** <li>[[SQLITE_FCNTL_JOURNAL_POINTER]]
** The [SQLITE_FCNTL_JOURNAL_POINTER] opcode is used to obtain a pointer
** to the [sqlite3_file] object associated with the journal file (either
** the [rollback journal] or the [write-ahead log]) for a particular database
** connection.  See also [SQLITE_FCNTL_FILE_POINTER].
**
** <li>[[SQLITE_FCNTL_SYNC_OMITTED]]
** The SQLITE_FCNTL_SYNC_OMITTED file-control is no longer used.
**
** <li>[[SQLITE_FCNTL_SYNC]]
** The [SQLITE_FCNTL_SYNC] opcode is generated internally by SQLite and
** sent to the VFS immediately before the xSync method is invoked on a
** database file descriptor. Or, if the xSync method is not invoked
** because the user has configured SQLite with
** [PRAGMA synchronous | PRAGMA synchronous=OFF] it is invoked in place
** of the xSync method. In most cases, the pointer argument passed with
** this file-control is NULL. However, if the database file is being synced
** as part of a multi-database commit, the argument points to a nul-terminated
** string containing the transactions super-journal file name. VFSes that
** do not need this signal should silently ignore this opcode. Applications
** should not call [sqlite3_file_control()] with this opcode as doing so may
** disrupt the operation of the specialized VFSes that do require it.
**
** <li>[[SQLITE_FCNTL_COMMIT_PHASETWO]]
** The [SQLITE_FCNTL_COMMIT_PHASETWO] opcode is generated internally by SQLite
** and sent to the VFS after a transaction has been committed immediately
** but before the database is unlocked. VFSes that do not need this signal
** should silently ignore this opcode. Applications should not call
** [sqlite3_file_control()] with this opcode as doing so may disrupt the
** operation of the specialized VFSes that do require it.
**
** <li>[[SQLITE_FCNTL_WIN32_AV_RETRY]]
** ^The [SQLITE_FCNTL_WIN32_AV_RETRY] opcode is used to configure automatic
** retry counts and intervals for certain disk I/O operations for the
** windows [VFS] in order to provide robustness in the presence of
** anti-virus programs.  By default, the windows VFS will retry file read,
** file write, and file delete operations up to 10 times, with a delay
** of 25 milliseconds before the first retry and with the delay increasing
** by an additional 25 milliseconds with each subsequent retry.  This
** opcode allows these two values (10 retries and 25 milliseconds of delay)
** to be adjusted.  The values are changed for all database connections
** within the same process.  The argument is a pointer to an array of two
** integers where the first integer is the new retry count and the second
** integer is the delay.  If either integer is negative, then the setting
** is not changed but instead the prior value of that setting is written
** into the array entry, allowing the current retry settings to be
** interrogated.  The zDbName parameter is ignored.
**
** <li>[[SQLITE_FCNTL_PERSIST_WAL]]
** ^The [SQLITE_FCNTL_PERSIST_WAL] opcode is used to set or query the
** persistent [WAL | Write Ahead Log] setting.  By default, the auxiliary
** write ahead log ([WAL file]) and shared memory
** files used for transaction control
** are automatically deleted when the latest connection to the database
** closes.  Setting persistent WAL mode causes those files to persist after
** close.  Persisting the files is useful when other processes that do not
** have write permission on the directory containing the database file want
** to read the database file, as the WAL and shared memory files must exist
** in order for the database to be readable.  The fourth parameter to
** [sqlite3_file_control()] for this opcode should be a pointer to an integer.
** That integer is 0 to disable persistent WAL mode or 1 to enable persistent
** WAL mode.  If the integer is -1, then it is overwritten with the current
** WAL persistence setting.
**
** <li>[[SQLITE_FCNTL_POWERSAFE_OVERWRITE]]
** ^The [SQLITE_FCNTL_POWERSAFE_OVERWRITE] opcode is used to set or query the
** persistent "powersafe-overwrite" or "PSOW" setting.  The PSOW setting
** determines the [SQLITE_IOCAP_POWERSAFE_OVERWRITE] bit of the
** xDeviceCharacteristics methods. The fourth parameter to
** [sqlite3_file_control()] for this opcode should be a pointer to an integer.
** That integer is 0 to disable zero-damage mode or 1 to enable zero-damage
** mode.  If the integer is -1, then it is overwritten with the current
** zero-damage mode setting.
**
** <li>[[SQLITE_FCNTL_OVERWRITE]]
** ^The [SQLITE_FCNTL_OVERWRITE] opcode is invoked by SQLite after opening
** a write transaction to indicate that, unless it is rolled back for some
** reason, the entire database file will be overwritten by the current
** transaction. This is used by VACUUM operations.
**
** <li>[[SQLITE_FCNTL_VFSNAME]]
** ^The [SQLITE_FCNTL_VFSNAME] opcode can be used to obtain the names of
** all [VFSes] in the VFS stack.  The names of all VFS shims and the
** final bottom-level VFS are written into memory obtained from
** [sqlite3_malloc()] and the result is stored in the char* variable
** that the fourth parameter of [sqlite3_file_control()] points to.
** The caller is responsible for freeing the memory when done.  As with
** all file-control actions, there is no guarantee that this will actually
** do anything.  Callers should initialize the char* variable to a NULL
** pointer in case this file-control is not implemented.  This file-control
** is intended for diagnostic use only.
**
** <li>[[SQLITE_FCNTL_VFS_POINTER]]
** ^The [SQLITE_FCNTL_VFS_POINTER] opcode finds a pointer to the top-level
** [VFSes] currently in use.  ^(The argument X in
** sqlite3_file_control(db,SQLITE_FCNTL_VFS_POINTER,X) must be
** of type "[sqlite3_vfs] **".  This opcode will set *X
** to a pointer to the top-level VFS.)^
** ^When there are multiple VFS shims in the stack, this opcode finds the
** upper-most shim only.
**
** <li>[[SQLITE_FCNTL_PRAGMA]]
** ^Whenever a [PRAGMA] statement is parsed, an [SQLITE_FCNTL_PRAGMA]
** file control is sent to the open [sqlite3_file] object corresponding
** to the database file to which the pragma statement refers. ^The argument
** to the [SQLITE_FCNTL_PRAGMA] file control is an array of
** pointers to strings (char**) in which the second element of the array
** is the name of the pragma and the third element is the argument to the
** pragma or NULL if the pragma has no argument.  ^The handler for an
** [SQLITE_FCNTL_PRAGMA] file control can optionally make the first element
** of the char** argument point to a string obtained from [sqlite3_mprintf()]
** or the equivalent and that string will become the result of the pragma or
** the error message if the pragma fails. ^If the
** [SQLITE_FCNTL_PRAGMA] file control returns [SQLITE_NOTFOUND], then normal
** [PRAGMA] processing continues.  ^If the [SQLITE_FCNTL_PRAGMA]
** file control returns [SQLITE_OK], then the parser assumes that the
** VFS has handled the PRAGMA itself and the parser generates a no-op
** prepared statement if result string is NULL, or that returns a copy
** of the result string if the string is non-NULL.
** ^If the [SQLITE_FCNTL_PRAGMA] file control returns
** any result code other than [SQLITE_OK] or [SQLITE_NOTFOUND], that means
** that the VFS encountered an error while handling the [PRAGMA] and the
** compilation of the PRAGMA fails with an error.  ^The [SQLITE_FCNTL_PRAGMA]
** file control occurs at the beginning of pragma statement analysis and so
** it is able to override built-in [PRAGMA] statements.
**
** <li>[[SQLITE_FCNTL_BUSYHANDLER]]
** ^The [SQLITE_FCNTL_BUSYHANDLER]
** file-control may be invoked by SQLite on the database file handle
** shortly after it is opened in order to provide a custom VFS with access
** to the connection's busy-handler callback. The argument is of type (void**)
** - an array of two (void *) values. The first (void *) actually points
** to a function of type (int (*)(void *)). In order to invoke the connection's
** busy-handler, this function should be invoked with the second (void *) in
** the array as the only argument. If it returns non-zero, then the operation
** should be retried. If it returns zero, the custom VFS should abandon the
** current operation.
**
** <li>[[SQLITE_FCNTL_TEMPFILENAME]]
** ^Applications can invoke the [SQLITE_FCNTL_TEMPFILENAME] file-control
** to have SQLite generate a
** temporary filename using the same algorithm that is followed to generate
** temporary filenames for TEMP tables and other internal uses.  The
** argument should be a char** which will be filled with the filename
** written into memory obtained from [sqlite3_malloc()].  The caller should
** invoke [sqlite3_free()] on the result to avoid a memory leak.
**
** <li>[[SQLITE_FCNTL_MMAP_SIZE]]
** The [SQLITE_FCNTL_MMAP_SIZE] file control is used to query or set the
** maximum number of bytes that will be used for memory-mapped I/O.
** The argument is a pointer to a value of type sqlite3_int64 that
** is an advisory maximum number of bytes in the file to memory map.  The
** pointer is overwritten with the old value.  The limit is not changed if
** the value originally pointed to is negative, and so the current limit
** can be queried by passing in a pointer to a negative number.  This
** file-control is used internally to implement [PRAGMA mmap_size].
**
** <li>[[SQLITE_FCNTL_TRACE]]
** The [SQLITE_FCNTL_TRACE] file control provides advisory information
** to the VFS about what the higher layers of the SQLite stack are doing.
** This file control is used by some VFS activity tracing [shims].
** The argument is a zero-terminated string.  Higher layers in the
** SQLite stack may generate instances of this file control if
** the [SQLITE_USE_FCNTL_TRACE] compile-time option is enabled.
**
** <li>[[SQLITE_FCNTL_HAS_MOVED]]
** The [SQLITE_FCNTL_HAS_MOVED] file control interprets its argument as a
** pointer to an integer and it writes a boolean into that integer depending
** on whether or not the file has been renamed, moved, or deleted since it
** was first opened.
**
** <li>[[SQLITE_FCNTL_WIN32_GET_HANDLE]]
** The [SQLITE_FCNTL_WIN32_GET_HANDLE] opcode can be used to obtain the
** underlying native file handle associated with a file handle.  This file
** control interprets its argument as a pointer to a native file handle and
** writes the resulting value there.
**
** <li>[[SQLITE_FCNTL_WIN32_SET_HANDLE]]
** The [SQLITE_FCNTL_WIN32_SET_HANDLE] opcode is used for debugging.  This
** opcode causes the xFileControl method to swap the file handle with the one
** pointed to by the pArg argument.  This capability is used during testing
** and only needs to be supported when SQLITE_TEST is defined.
**
** <li>[[SQLITE_FCNTL_NULL_IO]]
** The [SQLITE_FCNTL_NULL_IO] opcode sets the low-level file descriptor
** or file handle for the [sqlite3_file] object such that it will no longer
** read or write to the database file.
**
** <li>[[SQLITE_FCNTL_WAL_BLOCK]]
** The [SQLITE_FCNTL_WAL_BLOCK] is a signal to the VFS layer that it might
** be advantageous to block on the next WAL lock if the lock is not immediately
** available.  The WAL subsystem issues this signal during rare
** circumstances in order to fix a problem with priority inversion.
** Applications should <em>not</em> use this file-control.
**
** <li>[[SQLITE_FCNTL_ZIPVFS]]
** The [SQLITE_FCNTL_ZIPVFS] opcode is implemented by zipvfs only. All other
** VFS should return SQLITE_NOTFOUND for this opcode.
**
** <li>[[SQLITE_FCNTL_RBU]]
** The [SQLITE_FCNTL_RBU] opcode is implemented by the special VFS used by
** the RBU extension only.  All other VFS should return SQLITE_NOTFOUND for
** this opcode.
**
** <li>[[SQLITE_FCNTL_BEGIN_ATOMIC_WRITE]]
** If the [SQLITE_FCNTL_BEGIN_ATOMIC_WRITE] opcode returns SQLITE_OK, then
** the file descriptor is placed in "batch write mode", which
** means all subsequent write operations will be deferred and done
** atomically at the next [SQLITE_FCNTL_COMMIT_ATOMIC_WRITE].  Systems
** that do not support batch atomic writes will return SQLITE_NOTFOUND.
** ^Following a successful SQLITE_FCNTL_BEGIN_ATOMIC_WRITE and prior to
** the closing [SQLITE_FCNTL_COMMIT_ATOMIC_WRITE] or
** [SQLITE_FCNTL_ROLLBACK_ATOMIC_WRITE], SQLite will make
** no VFS interface calls on the same [sqlite3_file] file descriptor
** except for calls to the xWrite method and the xFileControl method
** with [SQLITE_FCNTL_SIZE_HINT].
**
** <li>[[SQLITE_FCNTL_COMMIT_ATOMIC_WRITE]]
** The [SQLITE_FCNTL_COMMIT_ATOMIC_WRITE] opcode causes all write
** operations since the previous successful call to
** [SQLITE_FCNTL_BEGIN_ATOMIC_WRITE] to be performed atomically.
** This file control returns [SQLITE_OK] if and only if the writes were
** all performed successfully and have been committed to persistent storage.
** ^Regardless of whether or not it is successful, this file control takes
** the file descriptor out of batch write mode so that all subsequent
** write operations are independent.
** ^SQLite will never invoke SQLITE_FCNTL_COMMIT_ATOMIC_WRITE without
** a prior successful call to [SQLITE_FCNTL_BEGIN_ATOMIC_WRITE].
**
** <li>[[SQLITE_FCNTL_ROLLBACK_ATOMIC_WRITE]]
** The [SQLITE_FCNTL_ROLLBACK_ATOMIC_WRITE] opcode causes all write
** operations since the previous successful call to
** [SQLITE_FCNTL_BEGIN_ATOMIC_WRITE] to be rolled back.
** ^This file control takes the file descriptor out of batch write mode
** so that all subsequent write operations are independent.
** ^SQLite will never invoke SQLITE_FCNTL_ROLLBACK_ATOMIC_WRITE without
** a prior successful call to [SQLITE_FCNTL_BEGIN_ATOMIC_WRITE].
**
** <li>[[SQLITE_FCNTL_LOCK_TIMEOUT]]
** The [SQLITE_FCNTL_LOCK_TIMEOUT] opcode is used to configure a VFS
** to block for up to M milliseconds before failing when attempting to
** obtain a file lock using the xLock or xShmLock methods of the VFS.
** The parameter is a pointer to a 32-bit signed integer that contains
** the value that M is to be set to. Before returning, the 32-bit signed
** integer is overwritten with the previous value of M.
**
** <li>[[SQLITE_FCNTL_BLOCK_ON_CONNECT]]
** The [SQLITE_FCNTL_BLOCK_ON_CONNECT] opcode is used to configure the
** VFS to block when taking a SHARED lock to connect to a wal mode database.
** This is used to implement the functionality associated with
** SQLITE_SETLK_BLOCK_ON_CONNECT.
**
** <li>[[SQLITE_FCNTL_DATA_VERSION]]
** The [SQLITE_FCNTL_DATA_VERSION] opcode is used to detect changes to
** a database file.  The argument is a pointer to a 32-bit unsigned integer.
** The "data version" for the pager is written into the pointer.  The
** "data version" changes whenever any change occurs to the corresponding
** database file, either through SQL statements on the same database
** connection or through transactions committed by separate database
** connections possibly in other processes. The [sqlite3_total_changes()]
** interface can be used to find if any database on the connection has changed,
** but that interface responds to changes on TEMP as well as MAIN and does
** not provide a mechanism to detect changes to MAIN only.  Also, the
** [sqlite3_total_changes()] interface responds to internal changes only and
** omits changes made by other database connections.  The
** [PRAGMA data_version] command provides a mechanism to detect changes to
** a single attached database that occur due to other database connections,
** but omits changes implemented by the database connection on which it is
** called.  This file control is the only mechanism to detect changes that
** happen either internally or externally and that are associated with
** a particular attached database.
**
** <li>[[SQLITE_FCNTL_CKPT_START]]
** The [SQLITE_FCNTL_CKPT_START] opcode is invoked from within a checkpoint
** in wal mode before the client starts to copy pages from the wal
** file to the database file.
**
** <li>[[SQLITE_FCNTL_CKPT_DONE]]
** The [SQLITE_FCNTL_CKPT_DONE] opcode is invoked from within a checkpoint
** in wal mode after the client has finished copying pages from the wal
** file to the database file, but before the *-shm file is updated to
** record the fact that the pages have been checkpointed.
**
** <li>[[SQLITE_FCNTL_EXTERNAL_READER]]
** The EXPERIMENTAL [SQLITE_FCNTL_EXTERNAL_READER] opcode is used to detect
** whether or not there is a database client in another process with a wal-mode
** transaction open on the database or not. It is only available on unix. The
** (void*) argument passed with this file-control should be a pointer to a
** value of type (int). The integer value is set to 1 if the database is a wal
** mode database and there exists at least one client in another process that
** currently has an SQL transaction open on the database. It is set to 0 if
** the database is not a wal-mode db, or if there is no such connection in any
** other process. This opcode cannot be used to detect transactions opened
** by clients within the current process, only within other processes.
**
** <li>[[SQLITE_FCNTL_CKSM_FILE]]
** The [SQLITE_FCNTL_CKSM_FILE] opcode is for use internally by the
** [checksum VFS shim] only.
**
** <li>[[SQLITE_FCNTL_RESET_CACHE]]
** If there is currently no transaction open on the database, and the
** database is not a temp db, then the [SQLITE_FCNTL_RESET_CACHE] file-control
** purges the contents of the in-memory page cache. If there is an open
** transaction, or if the db is a temp-db, this opcode is a no-op, not an error.
**
** <li>[[SQLITE_FCNTL_FILESTAT]]
** The [SQLITE_FCNTL_FILESTAT] opcode returns low-level diagnostic information
** about the [sqlite3_file] objects used access the database and journal files
** for the given schema.  The fourth parameter to [sqlite3_file_control()]
** should be an initialized [sqlite3_str] pointer.  JSON text describing
** various aspects of the sqlite3_file object is appended to the sqlite3_str.
** The SQLITE_FCNTL_FILESTAT opcode is usually a no-op, unless compile-time
** options are used to enable it.
** </ul>
*/
FCNTL_LOCKSTATE :: 1
FCNTL_GET_LOCKPROXYFILE :: 2
FCNTL_SET_LOCKPROXYFILE :: 3
FCNTL_LAST_ERRNO :: 4
FCNTL_SIZE_HINT :: 5
FCNTL_CHUNK_SIZE :: 6
FCNTL_FILE_POINTER :: 7
FCNTL_SYNC_OMITTED :: 8
FCNTL_WIN32_AV_RETRY :: 9
FCNTL_PERSIST_WAL :: 10
FCNTL_OVERWRITE :: 11
FCNTL_VFSNAME :: 12
FCNTL_POWERSAFE_OVERWRITE :: 13
FCNTL_PRAGMA :: 14
FCNTL_BUSYHANDLER :: 15
FCNTL_TEMPFILENAME :: 16
FCNTL_MMAP_SIZE :: 18
FCNTL_TRACE :: 19
FCNTL_HAS_MOVED :: 20
FCNTL_SYNC :: 21
FCNTL_COMMIT_PHASETWO :: 22
FCNTL_WIN32_SET_HANDLE :: 23
FCNTL_WAL_BLOCK :: 24
FCNTL_ZIPVFS :: 25
FCNTL_RBU :: 26
FCNTL_VFS_POINTER :: 27
FCNTL_JOURNAL_POINTER :: 28
FCNTL_WIN32_GET_HANDLE :: 29
FCNTL_PDB :: 30
FCNTL_BEGIN_ATOMIC_WRITE :: 31
FCNTL_COMMIT_ATOMIC_WRITE :: 32
FCNTL_ROLLBACK_ATOMIC_WRITE :: 33
FCNTL_LOCK_TIMEOUT :: 34
FCNTL_DATA_VERSION :: 35
FCNTL_SIZE_LIMIT :: 36
FCNTL_CKPT_DONE :: 37
FCNTL_RESERVE_BYTES :: 38
FCNTL_CKPT_START :: 39
FCNTL_EXTERNAL_READER :: 40
FCNTL_CKSM_FILE :: 41
FCNTL_RESET_CACHE :: 42
FCNTL_NULL_IO :: 43
FCNTL_BLOCK_ON_CONNECT :: 44
FCNTL_FILESTAT :: 45

/* deprecated names */
GET_LOCKPROXYFILE :: FCNTL_GET_LOCKPROXYFILE
SET_LOCKPROXYFILE :: FCNTL_SET_LOCKPROXYFILE
LAST_ERRNO :: FCNTL_LAST_ERRNO

Mutex :: struct {}

/*
** CAPI3REF: File Name
**
** Type [sqlite3_filename] is used by SQLite to pass filenames to the
** xOpen method of a [VFS]. It may be cast to (const char*) and treated
** as a normal, nul-terminated, UTF-8 buffer containing the filename, but
** may also be passed to special APIs such as:
**
** <ul>
** <li>  sqlite3_filename_database()
** <li>  sqlite3_filename_journal()
** <li>  sqlite3_filename_wal()
** <li>  sqlite3_uri_parameter()
** <li>  sqlite3_uri_boolean()
** <li>  sqlite3_uri_int64()
** <li>  sqlite3_uri_key()
** </ul>
*/
Filename :: cstring
Syscall_Ptr :: proc "c" ()

Vfs :: struct {
	iVersion:          i32, /* Structure version number (currently 3) */
	szOsFile:          i32, /* Size of subclassed sqlite3_file */
	mxPathname:        i32, /* Maximum file pathname length */
	pNext:             ^Vfs, /* Next registered VFS */
	zName:             cstring, /* Name of this virtual file system */
	pAppData:          rawptr, /* Pointer to application-specific data */
	xOpen:             proc "c" (_: ^Vfs, zName: Filename, _: ^File, flags: i32, pOutFlags: ^i32) -> i32,
	xDelete:           proc "c" (_: ^Vfs, zName: cstring, syncDir: i32) -> i32,
	xAccess:           proc "c" (_: ^Vfs, zName: cstring, flags: i32, pResOut: ^i32) -> i32,
	xFullPathname:     proc "c" (_: ^Vfs, zName: cstring, nOut: i32, zOut: cstring) -> i32,
	xDlOpen:           proc "c" (_: ^Vfs, zFilename: cstring) -> rawptr,
	xDlError:          proc "c" (_: ^Vfs, nByte: i32, zErrMsg: cstring),
	xDlSym:            proc "c" (_: ^Vfs, _: rawptr, zSymbol: cstring) -> proc "c" (),
	xDlClose:          proc "c" (_: ^Vfs, _: rawptr),
	xRandomness:       proc "c" (_: ^Vfs, nByte: i32, zOut: cstring) -> i32,
	xSleep:            proc "c" (_: ^Vfs, microseconds: i32) -> i32,
	xCurrentTime:      proc "c" (_: ^Vfs, _: ^f64) -> i32,
	xGetLastError:     proc "c" (_: ^Vfs, _: i32, _: cstring) -> i32,

	/*
	** The methods above are in version 1 of the sqlite_vfs object
	** definition.  Those that follow are added in version 2 or later
	*/
	xCurrentTimeInt64: proc "c" (_: ^Vfs, _: ^i64) -> i32,

	/*
	** The methods above are in versions 1 and 2 of the sqlite_vfs object.
	** Those below are for version 3 and greater.
	*/
	xSetSystemCall:    proc "c" (_: ^Vfs, zName: cstring, _: Syscall_Ptr) -> i32,
	xGetSystemCall:    proc "c" (_: ^Vfs, zName: cstring) -> Syscall_Ptr,
	xNextSystemCall:   proc "c" (_: ^Vfs, zName: cstring) -> cstring,
}

/*
** CAPI3REF: Flags for the xAccess VFS method
**
** These integer constants can be used as the third parameter to
** the xAccess method of an [sqlite3_vfs] object.  They determine
** what kind of permissions the xAccess method is looking for.
** With SQLITE_ACCESS_EXISTS, the xAccess method
** simply checks whether the file exists.
** With SQLITE_ACCESS_READWRITE, the xAccess method
** checks whether the named directory is both readable and writable
** (in other words, if files can be added, removed, and renamed within
** the directory).
** The SQLITE_ACCESS_READWRITE constant is currently used only by the
** [temp_store_directory pragma], though this could change in a future
** release of SQLite.
** With SQLITE_ACCESS_READ, the xAccess method
** checks whether the file is readable.  The SQLITE_ACCESS_READ constant is
** currently unused, though it might be used in a future release of
** SQLite.
*/
ACCESS_EXISTS :: 0
ACCESS_READWRITE :: 1 /* Used by PRAGMA temp_store_directory */
ACCESS_READ :: 2 /* Unused */

/*
** CAPI3REF: Flags for the xShmLock VFS method
**
** These integer constants define the various locking operations
** allowed by the xShmLock method of [sqlite3_io_methods].  The
** following are the only legal combinations of flags to the
** xShmLock method:
**
** <ul>
** <li>  SQLITE_SHM_LOCK | SQLITE_SHM_SHARED
** <li>  SQLITE_SHM_LOCK | SQLITE_SHM_EXCLUSIVE
** <li>  SQLITE_SHM_UNLOCK | SQLITE_SHM_SHARED
** <li>  SQLITE_SHM_UNLOCK | SQLITE_SHM_EXCLUSIVE
** </ul>
**
** When unlocking, the same SHARED or EXCLUSIVE flag must be supplied as
** was given on the corresponding lock.
**
** The xShmLock method can transition between unlocked and SHARED or
** between unlocked and EXCLUSIVE.  It cannot transition between SHARED
** and EXCLUSIVE.
*/
SHM_UNLOCK :: 1
SHM_LOCK :: 2
SHM_SHARED :: 4
SHM_EXCLUSIVE :: 8

/*
** CAPI3REF: Maximum xShmLock index
**
** The xShmLock method on [sqlite3_io_methods] may use values
** between 0 and this upper bound as its "offset" argument.
** The SQLite core will never attempt to acquire or release a
** lock outside of this range
*/
SHM_NLOCK :: 8


Mem_Methods :: struct {
	xMalloc:   proc "c" (
		_: i32,
		/* Memory allocation function */
	) -> rawptr, /* Memory allocation function */
	xFree:     proc "c" (
		_: rawptr,
		/* Free a prior allocation */
	), /* Free a prior allocation */
	xRealloc:  proc "c" (
		_: rawptr,
		_: i32,
		/* Resize an allocation */
	) -> rawptr, /* Resize an allocation */
	xSize:     proc "c" (
		_: rawptr,
		/* Return the size of an allocation */
	) -> i32, /* Return the size of an allocation */
	xRoundup:  proc "c" (
		_: i32,
		/* Round up request size to allocation size */
	) -> i32, /* Round up request size to allocation size */
	xInit:     proc "c" (
		_: rawptr,
		/* Initialize the memory allocator */
	) -> i32, /* Initialize the memory allocator */
	xShutdown: proc "c" (
		_: rawptr,
		/* Deinitialize the memory allocator */
	), /* Deinitialize the memory allocator */
	pAppData:  rawptr, /* Argument to xInit() and xShutdown() */
}

/*
** CAPI3REF: Configuration Options
** KEYWORDS: {configuration option}
**
** These constants are the available integer configuration options that
** can be passed as the first argument to the [sqlite3_config()] interface.
**
** Most of the configuration options for sqlite3_config()
** will only work if invoked prior to [sqlite3_initialize()] or after
** [sqlite3_shutdown()].  The few exceptions to this rule are called
** "anytime configuration options".
** ^Calling [sqlite3_config()] with a first argument that is not an
** anytime configuration option in between calls to [sqlite3_initialize()] and
** [sqlite3_shutdown()] is a no-op that returns SQLITE_MISUSE.
**
** The set of anytime configuration options can change (by insertions
** and/or deletions) from one release of SQLite to the next.
** As of SQLite version 3.42.0, the complete set of anytime configuration
** options is:
** <ul>
** <li> SQLITE_CONFIG_LOG
** <li> SQLITE_CONFIG_PCACHE_HDRSZ
** </ul>
**
** New configuration options may be added in future releases of SQLite.
** Existing configuration options might be discontinued.  Applications
** should check the return code from [sqlite3_config()] to make sure that
** the call worked.  The [sqlite3_config()] interface will return a
** non-zero [error code] if a discontinued or unsupported configuration option
** is invoked.
**
** <dl>
** [[SQLITE_CONFIG_SINGLETHREAD]] <dt>SQLITE_CONFIG_SINGLETHREAD</dt>
** <dd>There are no arguments to this option.  ^This option sets the
** [threading mode] to Single-thread.  In other words, it disables
** all mutexing and puts SQLite into a mode where it can only be used
** by a single thread.   ^If SQLite is compiled with
** the [SQLITE_THREADSAFE | SQLITE_THREADSAFE=0] compile-time option then
** it is not possible to change the [threading mode] from its default
** value of Single-thread and so [sqlite3_config()] will return
** [SQLITE_ERROR] if called with the SQLITE_CONFIG_SINGLETHREAD
** configuration option.</dd>
**
** [[SQLITE_CONFIG_MULTITHREAD]] <dt>SQLITE_CONFIG_MULTITHREAD</dt>
** <dd>There are no arguments to this option.  ^This option sets the
** [threading mode] to Multi-thread.  In other words, it disables
** mutexing on [database connection] and [prepared statement] objects.
** The application is responsible for serializing access to
** [database connections] and [prepared statements].  But other mutexes
** are enabled so that SQLite will be safe to use in a multi-threaded
** environment as long as no two threads attempt to use the same
** [database connection] at the same time.  ^If SQLite is compiled with
** the [SQLITE_THREADSAFE | SQLITE_THREADSAFE=0] compile-time option then
** it is not possible to set the Multi-thread [threading mode] and
** [sqlite3_config()] will return [SQLITE_ERROR] if called with the
** SQLITE_CONFIG_MULTITHREAD configuration option.</dd>
**
** [[SQLITE_CONFIG_SERIALIZED]] <dt>SQLITE_CONFIG_SERIALIZED</dt>
** <dd>There are no arguments to this option.  ^This option sets the
** [threading mode] to Serialized. In other words, this option enables
** all mutexes including the recursive
** mutexes on [database connection] and [prepared statement] objects.
** In this mode (which is the default when SQLite is compiled with
** [SQLITE_THREADSAFE=1]) the SQLite library will itself serialize access
** to [database connections] and [prepared statements] so that the
** application is free to use the same [database connection] or the
** same [prepared statement] in different threads at the same time.
** ^If SQLite is compiled with
** the [SQLITE_THREADSAFE | SQLITE_THREADSAFE=0] compile-time option then
** it is not possible to set the Serialized [threading mode] and
** [sqlite3_config()] will return [SQLITE_ERROR] if called with the
** SQLITE_CONFIG_SERIALIZED configuration option.</dd>
**
** [[SQLITE_CONFIG_MALLOC]] <dt>SQLITE_CONFIG_MALLOC</dt>
** <dd> ^(The SQLITE_CONFIG_MALLOC option takes a single argument which is
** a pointer to an instance of the [sqlite3_mem_methods] structure.
** The argument specifies
** alternative low-level memory allocation routines to be used in place of
** the memory allocation routines built into SQLite.)^ ^SQLite makes
** its own private copy of the content of the [sqlite3_mem_methods] structure
** before the [sqlite3_config()] call returns.</dd>
**
** [[SQLITE_CONFIG_GETMALLOC]] <dt>SQLITE_CONFIG_GETMALLOC</dt>
** <dd> ^(The SQLITE_CONFIG_GETMALLOC option takes a single argument which
** is a pointer to an instance of the [sqlite3_mem_methods] structure.
** The [sqlite3_mem_methods]
** structure is filled with the currently defined memory allocation routines.)^
** This option can be used to overload the default memory allocation
** routines with a wrapper that simulates memory allocation failure or
** tracks memory usage, for example. </dd>
**
** [[SQLITE_CONFIG_SMALL_MALLOC]] <dt>SQLITE_CONFIG_SMALL_MALLOC</dt>
** <dd> ^The SQLITE_CONFIG_SMALL_MALLOC option takes a single argument of
** type int, interpreted as a boolean, which if true provides a hint to
** SQLite that it should avoid large memory allocations if possible.
** SQLite will run faster if it is free to make large memory allocations,
** but some applications might prefer to run slower in exchange for
** guarantees about memory fragmentation that are possible if large
** allocations are avoided.  This hint is normally off.
** </dd>
**
** [[SQLITE_CONFIG_MEMSTATUS]] <dt>SQLITE_CONFIG_MEMSTATUS</dt>
** <dd> ^The SQLITE_CONFIG_MEMSTATUS option takes a single argument of type int,
** interpreted as a boolean, which enables or disables the collection of
** memory allocation statistics. ^(When memory allocation statistics are
** disabled, the following SQLite interfaces become non-operational:
**   <ul>
**   <li> [sqlite3_hard_heap_limit64()]
**   <li> [sqlite3_memory_used()]
**   <li> [sqlite3_memory_highwater()]
**   <li> [sqlite3_soft_heap_limit64()]
**   <li> [sqlite3_status64()]
**   </ul>)^
** ^Memory allocation statistics are enabled by default unless SQLite is
** compiled with [SQLITE_DEFAULT_MEMSTATUS]=0 in which case memory
** allocation statistics are disabled by default.
** </dd>
**
** [[SQLITE_CONFIG_SCRATCH]] <dt>SQLITE_CONFIG_SCRATCH</dt>
** <dd> The SQLITE_CONFIG_SCRATCH option is no longer used.
** </dd>
**
** [[SQLITE_CONFIG_PAGECACHE]] <dt>SQLITE_CONFIG_PAGECACHE</dt>
** <dd> ^The SQLITE_CONFIG_PAGECACHE option specifies a memory pool
** that SQLite can use for the database page cache with the default page
** cache implementation.
** This configuration option is a no-op if an application-defined page
** cache implementation is loaded using the [SQLITE_CONFIG_PCACHE2].
** ^There are three arguments to SQLITE_CONFIG_PAGECACHE: A pointer to
** 8-byte aligned memory (pMem), the size of each page cache line (sz),
** and the number of cache lines (N).
** The sz argument should be the size of the largest database page
** (a power of two between 512 and 65536) plus some extra bytes for each
** page header.  ^The number of extra bytes needed by the page header
** can be determined using [SQLITE_CONFIG_PCACHE_HDRSZ].
** ^It is harmless, apart from the wasted memory,
** for the sz parameter to be larger than necessary.  The pMem
** argument must be either a NULL pointer or a pointer to an 8-byte
** aligned block of memory of at least sz*N bytes, otherwise
** subsequent behavior is undefined.
** ^When pMem is not NULL, SQLite will strive to use the memory provided
** to satisfy page cache needs, falling back to [sqlite3_malloc()] if
** a page cache line is larger than sz bytes or if all of the pMem buffer
** is exhausted.
** ^If pMem is NULL and N is non-zero, then each database connection
** does an initial bulk allocation for page cache memory
** from [sqlite3_malloc()] sufficient for N cache lines if N is positive or
** of -1024*N bytes if N is negative. ^If additional
** page cache memory is needed beyond what is provided by the initial
** allocation, then SQLite goes to [sqlite3_malloc()] separately for each
** additional cache line. </dd>
**
** [[SQLITE_CONFIG_HEAP]] <dt>SQLITE_CONFIG_HEAP</dt>
** <dd> ^The SQLITE_CONFIG_HEAP option specifies a static memory buffer
** that SQLite will use for all of its dynamic memory allocation needs
** beyond those provided for by [SQLITE_CONFIG_PAGECACHE].
** ^The SQLITE_CONFIG_HEAP option is only available if SQLite is compiled
** with either [SQLITE_ENABLE_MEMSYS3] or [SQLITE_ENABLE_MEMSYS5] and returns
** [SQLITE_ERROR] if invoked otherwise.
** ^There are three arguments to SQLITE_CONFIG_HEAP:
** An 8-byte aligned pointer to the memory,
** the number of bytes in the memory buffer, and the minimum allocation size.
** ^If the first pointer (the memory pointer) is NULL, then SQLite reverts
** to using its default memory allocator (the system malloc() implementation),
** undoing any prior invocation of [SQLITE_CONFIG_MALLOC].  ^If the
** memory pointer is not NULL then the alternative memory
** allocator is engaged to handle all of SQLites memory allocation needs.
** The first pointer (the memory pointer) must be aligned to an 8-byte
** boundary or subsequent behavior of SQLite will be undefined.
** The minimum allocation size is capped at 2**12. Reasonable values
** for the minimum allocation size are 2**5 through 2**8.</dd>
**
** [[SQLITE_CONFIG_MUTEX]] <dt>SQLITE_CONFIG_MUTEX</dt>
** <dd> ^(The SQLITE_CONFIG_MUTEX option takes a single argument which is a
** pointer to an instance of the [sqlite3_mutex_methods] structure.
** The argument specifies alternative low-level mutex routines to be used
** in place of the mutex routines built into SQLite.)^  ^SQLite makes a copy of
** the content of the [sqlite3_mutex_methods] structure before the call to
** [sqlite3_config()] returns. ^If SQLite is compiled with
** the [SQLITE_THREADSAFE | SQLITE_THREADSAFE=0] compile-time option then
** the entire mutexing subsystem is omitted from the build and hence calls to
** [sqlite3_config()] with the SQLITE_CONFIG_MUTEX configuration option will
** return [SQLITE_ERROR].</dd>
**
** [[SQLITE_CONFIG_GETMUTEX]] <dt>SQLITE_CONFIG_GETMUTEX</dt>
** <dd> ^(The SQLITE_CONFIG_GETMUTEX option takes a single argument which
** is a pointer to an instance of the [sqlite3_mutex_methods] structure.  The
** [sqlite3_mutex_methods]
** structure is filled with the currently defined mutex routines.)^
** This option can be used to overload the default mutex allocation
** routines with a wrapper used to track mutex usage for performance
** profiling or testing, for example.   ^If SQLite is compiled with
** the [SQLITE_THREADSAFE | SQLITE_THREADSAFE=0] compile-time option then
** the entire mutexing subsystem is omitted from the build and hence calls to
** [sqlite3_config()] with the SQLITE_CONFIG_GETMUTEX configuration option will
** return [SQLITE_ERROR].</dd>
**
** [[SQLITE_CONFIG_LOOKASIDE]] <dt>SQLITE_CONFIG_LOOKASIDE</dt>
** <dd> ^(The SQLITE_CONFIG_LOOKASIDE option takes two arguments that determine
** the default size of [lookaside memory] on each [database connection].
** The first argument is the
** size of each lookaside buffer slot ("sz") and the second is the number of
** slots allocated to each database connection ("cnt").)^
** ^(SQLITE_CONFIG_LOOKASIDE sets the <i>default</i> lookaside size.
** The [SQLITE_DBCONFIG_LOOKASIDE] option to [sqlite3_db_config()] can
** be used to change the lookaside configuration on individual connections.)^
** The [-DSQLITE_DEFAULT_LOOKASIDE] option can be used to change the
** default lookaside configuration at compile-time.
** </dd>
**
** [[SQLITE_CONFIG_PCACHE2]] <dt>SQLITE_CONFIG_PCACHE2</dt>
** <dd> ^(The SQLITE_CONFIG_PCACHE2 option takes a single argument which is
** a pointer to an [sqlite3_pcache_methods2] object.  This object specifies
** the interface to a custom page cache implementation.)^
** ^SQLite makes a copy of the [sqlite3_pcache_methods2] object.</dd>
**
** [[SQLITE_CONFIG_GETPCACHE2]] <dt>SQLITE_CONFIG_GETPCACHE2</dt>
** <dd> ^(The SQLITE_CONFIG_GETPCACHE2 option takes a single argument which
** is a pointer to an [sqlite3_pcache_methods2] object.  SQLite copies off
** the current page cache implementation into that object.)^ </dd>
**
** [[SQLITE_CONFIG_LOG]] <dt>SQLITE_CONFIG_LOG</dt>
** <dd> The SQLITE_CONFIG_LOG option is used to configure the SQLite
** global [error log].
** (^The SQLITE_CONFIG_LOG option takes two arguments: a pointer to a
** function with a call signature of void(*)(void*,int,const char*),
** and a pointer to void. ^If the function pointer is not NULL, it is
** invoked by [sqlite3_log()] to process each logging event.  ^If the
** function pointer is NULL, the [sqlite3_log()] interface becomes a no-op.
** ^The void pointer that is the second argument to SQLITE_CONFIG_LOG is
** passed through as the first parameter to the application-defined logger
** function whenever that function is invoked.  ^The second parameter to
** the logger function is a copy of the first parameter to the corresponding
** [sqlite3_log()] call and is intended to be a [result code] or an
** [extended result code].  ^The third parameter passed to the logger is
** a log message after formatting via [sqlite3_snprintf()].
** The SQLite logging interface is not reentrant; the logger function
** supplied by the application must not invoke any SQLite interface.
** In a multi-threaded application, the application-defined logger
** function must be threadsafe. </dd>
**
** [[SQLITE_CONFIG_URI]] <dt>SQLITE_CONFIG_URI
** <dd>^(The SQLITE_CONFIG_URI option takes a single argument of type int.
** If non-zero, then URI handling is globally enabled. If the parameter is zero,
** then URI handling is globally disabled.)^ ^If URI handling is globally
** enabled, all filenames passed to [sqlite3_open()], [sqlite3_open_v2()],
** [sqlite3_open16()] or
** specified as part of [ATTACH] commands are interpreted as URIs, regardless
** of whether or not the [SQLITE_OPEN_URI] flag is set when the database
** connection is opened. ^If it is globally disabled, filenames are
** only interpreted as URIs if the SQLITE_OPEN_URI flag is set when the
** database connection is opened. ^(By default, URI handling is globally
** disabled. The default value may be changed by compiling with the
** [SQLITE_USE_URI] symbol defined.)^
**
** [[SQLITE_CONFIG_COVERING_INDEX_SCAN]] <dt>SQLITE_CONFIG_COVERING_INDEX_SCAN
** <dd>^The SQLITE_CONFIG_COVERING_INDEX_SCAN option takes a single integer
** argument which is interpreted as a boolean in order to enable or disable
** the use of covering indices for full table scans in the query optimizer.
** ^The default setting is determined
** by the [SQLITE_ALLOW_COVERING_INDEX_SCAN] compile-time option, or is "on"
** if that compile-time option is omitted.
** The ability to disable the use of covering indices for full table scans
** is because some incorrectly coded legacy applications might malfunction
** when the optimization is enabled.  Providing the ability to
** disable the optimization allows the older, buggy application code to work
** without change even with newer versions of SQLite.
**
** [[SQLITE_CONFIG_PCACHE]] [[SQLITE_CONFIG_GETPCACHE]]
** <dt>SQLITE_CONFIG_PCACHE and SQLITE_CONFIG_GETPCACHE
** <dd> These options are obsolete and should not be used by new code.
** They are retained for backwards compatibility but are now no-ops.
** </dd>
**
** [[SQLITE_CONFIG_SQLLOG]]
** <dt>SQLITE_CONFIG_SQLLOG
** <dd>This option is only available if sqlite is compiled with the
** [SQLITE_ENABLE_SQLLOG] pre-processor macro defined. The first argument should
** be a pointer to a function of type void(*)(void*,sqlite3*,const char*, int).
** The second should be of type (void*). The callback is invoked by the library
** in three separate circumstances, identified by the value passed as the
** fourth parameter. If the fourth parameter is 0, then the database connection
** passed as the second argument has just been opened. The third argument
** points to a buffer containing the name of the main database file. If the
** fourth parameter is 1, then the SQL statement that the third parameter
** points to has just been executed. Or, if the fourth parameter is 2, then
** the connection being passed as the second parameter is being closed. The
** third parameter is passed NULL In this case.  An example of using this
** configuration option can be seen in the "test_sqllog.c" source file in
** the canonical SQLite source tree.</dd>
**
** [[SQLITE_CONFIG_MMAP_SIZE]]
** <dt>SQLITE_CONFIG_MMAP_SIZE
** <dd>^SQLITE_CONFIG_MMAP_SIZE takes two 64-bit integer (sqlite3_int64) values
** that are the default mmap size limit (the default setting for
** [PRAGMA mmap_size]) and the maximum allowed mmap size limit.
** ^The default setting can be overridden by each database connection using
** either the [PRAGMA mmap_size] command, or by using the
** [SQLITE_FCNTL_MMAP_SIZE] file control.  ^(The maximum allowed mmap size
** will be silently truncated if necessary so that it does not exceed the
** compile-time maximum mmap size set by the
** [SQLITE_MAX_MMAP_SIZE] compile-time option.)^
** ^If either argument to this option is negative, then that argument is
** changed to its compile-time default.
**
** [[SQLITE_CONFIG_WIN32_HEAPSIZE]]
** <dt>SQLITE_CONFIG_WIN32_HEAPSIZE
** <dd>^The SQLITE_CONFIG_WIN32_HEAPSIZE option is only available if SQLite is
** compiled for Windows with the [SQLITE_WIN32_MALLOC] pre-processor macro
** defined. ^SQLITE_CONFIG_WIN32_HEAPSIZE takes a 32-bit unsigned integer value
** that specifies the maximum size of the created heap.
**
** [[SQLITE_CONFIG_PCACHE_HDRSZ]]
** <dt>SQLITE_CONFIG_PCACHE_HDRSZ
** <dd>^The SQLITE_CONFIG_PCACHE_HDRSZ option takes a single parameter which
** is a pointer to an integer and writes into that integer the number of extra
** bytes per page required for each page in [SQLITE_CONFIG_PAGECACHE].
** The amount of extra space required can change depending on the compiler,
** target platform, and SQLite version.
**
** [[SQLITE_CONFIG_PMASZ]]
** <dt>SQLITE_CONFIG_PMASZ
** <dd>^The SQLITE_CONFIG_PMASZ option takes a single parameter which
** is an unsigned integer and sets the "Minimum PMA Size" for the multithreaded
** sorter to that integer.  The default minimum PMA Size is set by the
** [SQLITE_SORTER_PMASZ] compile-time option.  New threads are launched
** to help with sort operations when multithreaded sorting
** is enabled (using the [PRAGMA threads] command) and the amount of content
** to be sorted exceeds the page size times the minimum of the
** [PRAGMA cache_size] setting and this value.
**
** [[SQLITE_CONFIG_STMTJRNL_SPILL]]
** <dt>SQLITE_CONFIG_STMTJRNL_SPILL
** <dd>^The SQLITE_CONFIG_STMTJRNL_SPILL option takes a single parameter which
** becomes the [statement journal] spill-to-disk threshold.
** [Statement journals] are held in memory until their size (in bytes)
** exceeds this threshold, at which point they are written to disk.
** Or if the threshold is -1, statement journals are always held
** exclusively in memory.
** Since many statement journals never become large, setting the spill
** threshold to a value such as 64KiB can greatly reduce the amount of
** I/O required to support statement rollback.
** The default value for this setting is controlled by the
** [SQLITE_STMTJRNL_SPILL] compile-time option.
**
** [[SQLITE_CONFIG_SORTERREF_SIZE]]
** <dt>SQLITE_CONFIG_SORTERREF_SIZE
** <dd>The SQLITE_CONFIG_SORTERREF_SIZE option accepts a single parameter
** of type (int) - the new value of the sorter-reference size threshold.
** Usually, when SQLite uses an external sort to order records according
** to an ORDER BY clause, all fields required by the caller are present in the
** sorted records. However, if SQLite determines based on the declared type
** of a table column that its values are likely to be very large - larger
** than the configured sorter-reference size threshold - then a reference
** is stored in each sorted record and the required column values loaded
** from the database as records are returned in sorted order. The default
** value for this option is to never use this optimization. Specifying a
** negative value for this option restores the default behavior.
** This option is only available if SQLite is compiled with the
** [SQLITE_ENABLE_SORTER_REFERENCES] compile-time option.
**
** [[SQLITE_CONFIG_MEMDB_MAXSIZE]]
** <dt>SQLITE_CONFIG_MEMDB_MAXSIZE
** <dd>The SQLITE_CONFIG_MEMDB_MAXSIZE option accepts a single parameter
** [sqlite3_int64] parameter which is the default maximum size for an in-memory
** database created using [sqlite3_deserialize()].  This default maximum
** size can be adjusted up or down for individual databases using the
** [SQLITE_FCNTL_SIZE_LIMIT] [sqlite3_file_control|file-control].  If this
** configuration setting is never used, then the default maximum is determined
** by the [SQLITE_MEMDB_DEFAULT_MAXSIZE] compile-time option.  If that
** compile-time option is not set, then the default maximum is 1073741824.
**
** [[SQLITE_CONFIG_ROWID_IN_VIEW]]
** <dt>SQLITE_CONFIG_ROWID_IN_VIEW
** <dd>The SQLITE_CONFIG_ROWID_IN_VIEW option enables or disables the ability
** for VIEWs to have a ROWID.  The capability can only be enabled if SQLite is
** compiled with -DSQLITE_ALLOW_ROWID_IN_VIEW, in which case the capability
** defaults to on.  This configuration option queries the current setting or
** changes the setting to off or on.  The argument is a pointer to an integer.
** If that integer initially holds a value of 1, then the ability for VIEWs to
** have ROWIDs is activated.  If the integer initially holds zero, then the
** ability is deactivated.  Any other initial value for the integer leaves the
** setting unchanged.  After changes, if any, the integer is written with
** a 1 or 0, if the ability for VIEWs to have ROWIDs is on or off.  If SQLite
** is compiled without -DSQLITE_ALLOW_ROWID_IN_VIEW (which is the usual and
** recommended case) then the integer is always filled with zero, regardless
** if its initial value.
** </dl>
*/
CONFIG_SINGLETHREAD :: 1 /* nil */
CONFIG_MULTITHREAD :: 2 /* nil */
CONFIG_SERIALIZED :: 3 /* nil */
CONFIG_MALLOC :: 4 /* sqlite3_mem_methods* */
CONFIG_GETMALLOC :: 5 /* sqlite3_mem_methods* */
CONFIG_SCRATCH :: 6 /* No longer used */
CONFIG_PAGECACHE :: 7 /* void*, int sz, int N */
CONFIG_HEAP :: 8 /* void*, int nByte, int min */
CONFIG_MEMSTATUS :: 9 /* boolean */
CONFIG_MUTEX :: 10 /* sqlite3_mutex_methods* */
CONFIG_GETMUTEX :: 11 /* sqlite3_mutex_methods* */

/* previously SQLITE_CONFIG_CHUNKALLOC    12 which is now unused. */
CONFIG_LOOKASIDE :: 13 /* int int */
CONFIG_PCACHE :: 14 /* no-op */
CONFIG_GETPCACHE :: 15 /* no-op */
CONFIG_LOG :: 16 /* xFunc, void* */
CONFIG_URI :: 17 /* int */
CONFIG_PCACHE2 :: 18 /* sqlite3_pcache_methods2* */
CONFIG_GETPCACHE2 :: 19 /* sqlite3_pcache_methods2* */
CONFIG_COVERING_INDEX_SCAN :: 20 /* int */
CONFIG_SQLLOG :: 21 /* xSqllog, void* */
CONFIG_MMAP_SIZE :: 22 /* sqlite3_int64, sqlite3_int64 */
CONFIG_WIN32_HEAPSIZE :: 23 /* int nByte */
CONFIG_PCACHE_HDRSZ :: 24 /* int *psz */
CONFIG_PMASZ :: 25 /* unsigned int szPma */
CONFIG_STMTJRNL_SPILL :: 26 /* int nByte */
CONFIG_SMALL_MALLOC :: 27 /* boolean */
CONFIG_SORTERREF_SIZE :: 28 /* int nByte */
CONFIG_MEMDB_MAXSIZE :: 29 /* sqlite3_int64 */
CONFIG_ROWID_IN_VIEW :: 30 /* int* */

/*
** CAPI3REF: Database Connection Configuration Options
**
** These constants are the available integer configuration options that
** can be passed as the second parameter to the [sqlite3_db_config()] interface.
**
** The [sqlite3_db_config()] interface is a var-args function.  It takes a
** variable number of parameters, though always at least two.  The number of
** parameters passed into sqlite3_db_config() depends on which of these
** constants is given as the second parameter.  This documentation page
** refers to parameters beyond the second as "arguments".  Thus, when this
** page says "the N-th argument" it means "the N-th parameter past the
** configuration option" or "the (N+2)-th parameter to sqlite3_db_config()".
**
** New configuration options may be added in future releases of SQLite.
** Existing configuration options might be discontinued.  Applications
** should check the return code from [sqlite3_db_config()] to make sure that
** the call worked.  ^The [sqlite3_db_config()] interface will return a
** non-zero [error code] if a discontinued or unsupported configuration option
** is invoked.
**
** <dl>
** [[SQLITE_DBCONFIG_LOOKASIDE]]
** <dt>SQLITE_DBCONFIG_LOOKASIDE</dt>
** <dd> The SQLITE_DBCONFIG_LOOKASIDE option is used to adjust the
** configuration of the [lookaside memory allocator] within a database
** connection.
** The arguments to the SQLITE_DBCONFIG_LOOKASIDE option are <i>not</i>
** in the [DBCONFIG arguments|usual format].
** The SQLITE_DBCONFIG_LOOKASIDE option takes three arguments, not two,
** so that a call to [sqlite3_db_config()] that uses SQLITE_DBCONFIG_LOOKASIDE
** should have a total of five parameters.
** <ol>
** <li><p>The first argument ("buf") is a
** pointer to a memory buffer to use for lookaside memory.
** The first argument may be NULL in which case SQLite will allocate the
** lookaside buffer itself using [sqlite3_malloc()].
** <li><P>The second argument ("sz") is the
** size of each lookaside buffer slot.  Lookaside is disabled if "sz"
** is less than 8.  The "sz" argument should be a multiple of 8 less than
** 65536.  If "sz" does not meet this constraint, it is reduced in size until
** it does.
** <li><p>The third argument ("cnt") is the number of slots.
** Lookaside is disabled if "cnt"is less than 1.
*  The "cnt" value will be reduced, if necessary, so
** that the product of "sz" and "cnt" does not exceed 2,147,418,112. The "cnt"
** parameter is usually chosen so that the product of "sz" and "cnt" is less
** than 1,000,000.
** </ol>
** <p>If the "buf" argument is not NULL, then it must
** point to a memory buffer with a size that is greater than
** or equal to the product of "sz" and "cnt".
** The buffer must be aligned to an 8-byte boundary.
** The lookaside memory
** configuration for a database connection can only be changed when that
** connection is not currently using lookaside memory, or in other words
** when the value returned by [SQLITE_DBSTATUS_LOOKASIDE_USED] is zero.
** Any attempt to change the lookaside memory configuration when lookaside
** memory is in use leaves the configuration unchanged and returns
** [SQLITE_BUSY].
** If the "buf" argument is NULL and an attempt
** to allocate memory based on "sz" and "cnt" fails, then
** lookaside is silently disabled.
** <p>
** The [SQLITE_CONFIG_LOOKASIDE] configuration option can be used to set the
** default lookaside configuration at initialization.  The
** [-DSQLITE_DEFAULT_LOOKASIDE] option can be used to set the default lookaside
** configuration at compile-time.  Typical values for lookaside are 1200 for
** "sz" and 40 to 100 for "cnt".
** </dd>
**
** [[SQLITE_DBCONFIG_ENABLE_FKEY]]
** <dt>SQLITE_DBCONFIG_ENABLE_FKEY</dt>
** <dd> ^This option is used to enable or disable the enforcement of
** [foreign key constraints].  This is the same setting that is
** enabled or disabled by the [PRAGMA foreign_keys] statement.
** The first argument is an integer which is 0 to disable FK enforcement,
** positive to enable FK enforcement or negative to leave FK enforcement
** unchanged.  The second parameter is a pointer to an integer into which
** is written 0 or 1 to indicate whether FK enforcement is off or on
** following this call.  The second parameter may be a NULL pointer, in
** which case the FK enforcement setting is not reported back. </dd>
**
** [[SQLITE_DBCONFIG_ENABLE_TRIGGER]]
** <dt>SQLITE_DBCONFIG_ENABLE_TRIGGER</dt>
** <dd> ^This option is used to enable or disable [CREATE TRIGGER | triggers].
** There should be two additional arguments.
** The first argument is an integer which is 0 to disable triggers,
** positive to enable triggers or negative to leave the setting unchanged.
** The second parameter is a pointer to an integer into which
** is written 0 or 1 to indicate whether triggers are disabled or enabled
** following this call.  The second parameter may be a NULL pointer, in
** which case the trigger setting is not reported back.
**
** <p>Originally this option disabled all triggers.  ^(However, since
** SQLite version 3.35.0, TEMP triggers are still allowed even if
** this option is off.  So, in other words, this option now only disables
** triggers in the main database schema or in the schemas of [ATTACH]-ed
** databases.)^ </dd>
**
** [[SQLITE_DBCONFIG_ENABLE_VIEW]]
** <dt>SQLITE_DBCONFIG_ENABLE_VIEW</dt>
** <dd> ^This option is used to enable or disable [CREATE VIEW | views].
** There must be two additional arguments.
** The first argument is an integer which is 0 to disable views,
** positive to enable views or negative to leave the setting unchanged.
** The second parameter is a pointer to an integer into which
** is written 0 or 1 to indicate whether views are disabled or enabled
** following this call.  The second parameter may be a NULL pointer, in
** which case the view setting is not reported back.
**
** <p>Originally this option disabled all views.  ^(However, since
** SQLite version 3.35.0, TEMP views are still allowed even if
** this option is off.  So, in other words, this option now only disables
** views in the main database schema or in the schemas of ATTACH-ed
** databases.)^ </dd>
**
** [[SQLITE_DBCONFIG_ENABLE_FTS3_TOKENIZER]]
** <dt>SQLITE_DBCONFIG_ENABLE_FTS3_TOKENIZER</dt>
** <dd> ^This option is used to enable or disable using the
** [fts3_tokenizer()] function - part of the [FTS3] full-text search engine
** extension - without using bound parameters as the parameters. Doing so
** is disabled by default. There must be two additional arguments. The first
** argument is an integer. If it is passed 0, then using fts3_tokenizer()
** without bound parameters is disabled. If it is passed a positive value,
** then calling fts3_tokenizer without bound parameters is enabled. If it
** is passed a negative value, this setting is not modified - this can be
** used to query for the current setting. The second parameter is a pointer
** to an integer into which is written 0 or 1 to indicate the current value
** of this setting (after it is modified, if applicable).  The second
** parameter may be a NULL pointer, in which case the value of the setting
** is not reported back. Refer to [FTS3] documentation for further details.
** </dd>
**
** [[SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION]]
** <dt>SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION</dt>
** <dd> ^This option is used to enable or disable the [sqlite3_load_extension()]
** interface independently of the [load_extension()] SQL function.
** The [sqlite3_enable_load_extension()] API enables or disables both the
** C-API [sqlite3_load_extension()] and the SQL function [load_extension()].
** There must be two additional arguments.
** When the first argument to this interface is 1, then only the C-API is
** enabled and the SQL function remains disabled.  If the first argument to
** this interface is 0, then both the C-API and the SQL function are disabled.
** If the first argument is -1, then no changes are made to the state of either
** the C-API or the SQL function.
** The second parameter is a pointer to an integer into which
** is written 0 or 1 to indicate whether [sqlite3_load_extension()] interface
** is disabled or enabled following this call.  The second parameter may
** be a NULL pointer, in which case the new setting is not reported back.
** </dd>
**
** [[SQLITE_DBCONFIG_MAINDBNAME]] <dt>SQLITE_DBCONFIG_MAINDBNAME</dt>
** <dd> ^This option is used to change the name of the "main" database
** schema.  This option does not follow the
** [DBCONFIG arguments|usual SQLITE_DBCONFIG argument format].
** This option takes exactly one additional argument so that the
** [sqlite3_db_config()] call has a total of three parameters.  The
** extra argument must be a pointer to a constant UTF8 string which
** will become the new schema name in place of "main".  ^SQLite does
** not make a copy of the new main schema name string, so the application
** must ensure that the argument passed into SQLITE_DBCONFIG MAINDBNAME
** is unchanged until after the database connection closes.
** </dd>
**
** [[SQLITE_DBCONFIG_NO_CKPT_ON_CLOSE]]
** <dt>SQLITE_DBCONFIG_NO_CKPT_ON_CLOSE</dt>
** <dd> Usually, when a database in [WAL mode] is closed or detached from a
** database handle, SQLite checks if if there are other connections to the
** same database, and if there are no other database connection (if the
** connection being closed is the last open connection to the database),
** then SQLite performs a [checkpoint] before closing the connection and
** deletes the WAL file.  The SQLITE_DBCONFIG_NO_CKPT_ON_CLOSE option can
** be used to override that behavior. The first argument passed to this
** operation (the third parameter to [sqlite3_db_config()]) is an integer
** which is positive to disable checkpoints-on-close, or zero (the default)
** to enable them, and negative to leave the setting unchanged.
** The second argument (the fourth parameter) is a pointer to an integer
** into which is written 0 or 1 to indicate whether checkpoints-on-close
** have been disabled - 0 if they are not disabled, 1 if they are.
** </dd>
**
** [[SQLITE_DBCONFIG_ENABLE_QPSG]] <dt>SQLITE_DBCONFIG_ENABLE_QPSG</dt>
** <dd>^(The SQLITE_DBCONFIG_ENABLE_QPSG option activates or deactivates
** the [query planner stability guarantee] (QPSG).  When the QPSG is active,
** a single SQL query statement will always use the same algorithm regardless
** of values of [bound parameters].)^ The QPSG disables some query optimizations
** that look at the values of bound parameters, which can make some queries
** slower.  But the QPSG has the advantage of more predictable behavior.  With
** the QPSG active, SQLite will always use the same query plan in the field as
** was used during testing in the lab.
** The first argument to this setting is an integer which is 0 to disable
** the QPSG, positive to enable QPSG, or negative to leave the setting
** unchanged. The second parameter is a pointer to an integer into which
** is written 0 or 1 to indicate whether the QPSG is disabled or enabled
** following this call.
** </dd>
**
** [[SQLITE_DBCONFIG_TRIGGER_EQP]] <dt>SQLITE_DBCONFIG_TRIGGER_EQP</dt>
** <dd> By default, the output of EXPLAIN QUERY PLAN commands does not
** include output for any operations performed by trigger programs. This
** option is used to set or clear (the default) a flag that governs this
** behavior. The first parameter passed to this operation is an integer -
** positive to enable output for trigger programs, or zero to disable it,
** or negative to leave the setting unchanged.
** The second parameter is a pointer to an integer into which is written
** 0 or 1 to indicate whether output-for-triggers has been disabled - 0 if
** it is not disabled, 1 if it is.
** </dd>
**
** [[SQLITE_DBCONFIG_RESET_DATABASE]] <dt>SQLITE_DBCONFIG_RESET_DATABASE</dt>
** <dd> Set the SQLITE_DBCONFIG_RESET_DATABASE flag and then run
** [VACUUM] in order to reset a database back to an empty database
** with no schema and no content. The following process works even for
** a badly corrupted database file:
** <ol>
** <li> If the database connection is newly opened, make sure it has read the
**      database schema by preparing then discarding some query against the
**      database, or calling sqlite3_table_column_metadata(), ignoring any
**      errors.  This step is only necessary if the application desires to keep
**      the database in WAL mode after the reset if it was in WAL mode before
**      the reset.
** <li> sqlite3_db_config(db, SQLITE_DBCONFIG_RESET_DATABASE, 1, 0);
** <li> [sqlite3_exec](db, "[VACUUM]", 0, 0, 0);
** <li> sqlite3_db_config(db, SQLITE_DBCONFIG_RESET_DATABASE, 0, 0);
** </ol>
** Because resetting a database is destructive and irreversible, the
** process requires the use of this obscure API and multiple steps to
** help ensure that it does not happen by accident. Because this
** feature must be capable of resetting corrupt databases, and
** shutting down virtual tables may require access to that corrupt
** storage, the library must abandon any installed virtual tables
** without calling their xDestroy() methods.
**
** [[SQLITE_DBCONFIG_DEFENSIVE]] <dt>SQLITE_DBCONFIG_DEFENSIVE</dt>
** <dd>The SQLITE_DBCONFIG_DEFENSIVE option activates or deactivates the
** "defensive" flag for a database connection.  When the defensive
** flag is enabled, language features that allow ordinary SQL to
** deliberately corrupt the database file are disabled.  The disabled
** features include but are not limited to the following:
** <ul>
** <li> The [PRAGMA writable_schema=ON] statement.
** <li> The [PRAGMA journal_mode=OFF] statement.
** <li> The [PRAGMA schema_version=N] statement.
** <li> Writes to the [sqlite_dbpage] virtual table.
** <li> Direct writes to [shadow tables].
** </ul>
** </dd>
**
** [[SQLITE_DBCONFIG_WRITABLE_SCHEMA]] <dt>SQLITE_DBCONFIG_WRITABLE_SCHEMA</dt>
** <dd>The SQLITE_DBCONFIG_WRITABLE_SCHEMA option activates or deactivates the
** "writable_schema" flag. This has the same effect and is logically equivalent
** to setting [PRAGMA writable_schema=ON] or [PRAGMA writable_schema=OFF].
** The first argument to this setting is an integer which is 0 to disable
** the writable_schema, positive to enable writable_schema, or negative to
** leave the setting unchanged. The second parameter is a pointer to an
** integer into which is written 0 or 1 to indicate whether the writable_schema
** is enabled or disabled following this call.
** </dd>
**
** [[SQLITE_DBCONFIG_LEGACY_ALTER_TABLE]]
** <dt>SQLITE_DBCONFIG_LEGACY_ALTER_TABLE</dt>
** <dd>The SQLITE_DBCONFIG_LEGACY_ALTER_TABLE option activates or deactivates
** the legacy behavior of the [ALTER TABLE RENAME] command such that it
** behaves as it did prior to [version 3.24.0] (2018-06-04).  See the
** "Compatibility Notice" on the [ALTER TABLE RENAME documentation] for
** additional information. This feature can also be turned on and off
** using the [PRAGMA legacy_alter_table] statement.
** </dd>
**
** [[SQLITE_DBCONFIG_DQS_DML]]
** <dt>SQLITE_DBCONFIG_DQS_DML</dt>
** <dd>The SQLITE_DBCONFIG_DQS_DML option activates or deactivates
** the legacy [double-quoted string literal] misfeature for DML statements
** only, that is DELETE, INSERT, SELECT, and UPDATE statements. The
** default value of this setting is determined by the [-DSQLITE_DQS]
** compile-time option.
** </dd>
**
** [[SQLITE_DBCONFIG_DQS_DDL]]
** <dt>SQLITE_DBCONFIG_DQS_DDL</dt>
** <dd>The SQLITE_DBCONFIG_DQS option activates or deactivates
** the legacy [double-quoted string literal] misfeature for DDL statements,
** such as CREATE TABLE and CREATE INDEX. The
** default value of this setting is determined by the [-DSQLITE_DQS]
** compile-time option.
** </dd>
**
** [[SQLITE_DBCONFIG_TRUSTED_SCHEMA]]
** <dt>SQLITE_DBCONFIG_TRUSTED_SCHEMA</dt>
** <dd>The SQLITE_DBCONFIG_TRUSTED_SCHEMA option tells SQLite to
** assume that database schemas are untainted by malicious content.
** When the SQLITE_DBCONFIG_TRUSTED_SCHEMA option is disabled, SQLite
** takes additional defensive steps to protect the application from harm
** including:
** <ul>
** <li> Prohibit the use of SQL functions inside triggers, views,
** CHECK constraints, DEFAULT clauses, expression indexes,
** partial indexes, or generated columns
** unless those functions are tagged with [SQLITE_INNOCUOUS].
** <li> Prohibit the use of virtual tables inside of triggers or views
** unless those virtual tables are tagged with [SQLITE_VTAB_INNOCUOUS].
** </ul>
** This setting defaults to "on" for legacy compatibility, however
** all applications are advised to turn it off if possible. This setting
** can also be controlled using the [PRAGMA trusted_schema] statement.
** </dd>
**
** [[SQLITE_DBCONFIG_LEGACY_FILE_FORMAT]]
** <dt>SQLITE_DBCONFIG_LEGACY_FILE_FORMAT</dt>
** <dd>The SQLITE_DBCONFIG_LEGACY_FILE_FORMAT option activates or deactivates
** the legacy file format flag.  When activated, this flag causes all newly
** created database files to have a schema format version number (the 4-byte
** integer found at offset 44 into the database header) of 1.  This in turn
** means that the resulting database file will be readable and writable by
** any SQLite version back to 3.0.0 ([dateof:3.0.0]).  Without this setting,
** newly created databases are generally not understandable by SQLite versions
** prior to 3.3.0 ([dateof:3.3.0]).  As these words are written, there
** is now scarcely any need to generate database files that are compatible
** all the way back to version 3.0.0, and so this setting is of little
** practical use, but is provided so that SQLite can continue to claim the
** ability to generate new database files that are compatible with  version
** 3.0.0.
** <p>Note that when the SQLITE_DBCONFIG_LEGACY_FILE_FORMAT setting is on,
** the [VACUUM] command will fail with an obscure error when attempting to
** process a table with generated columns and a descending index.  This is
** not considered a bug since SQLite versions 3.3.0 and earlier do not support
** either generated columns or descending indexes.
** </dd>
**
** [[SQLITE_DBCONFIG_STMT_SCANSTATUS]]
** <dt>SQLITE_DBCONFIG_STMT_SCANSTATUS</dt>
** <dd>The SQLITE_DBCONFIG_STMT_SCANSTATUS option is only useful in
** [SQLITE_ENABLE_STMT_SCANSTATUS] builds. In this case, it sets or clears
** a flag that enables collection of run-time performance statistics
** used by [sqlite3_stmt_scanstatus_v2()] and the [nexec and ncycle]
** columns of the [bytecode virtual table].
** For statistics to be collected, the flag must be set on
** the database handle both when the SQL statement is
** [sqlite3_prepare|prepared] and when it is [sqlite3_step|stepped].
** The flag is set (collection of statistics is enabled) by default.
** <p>This option takes two arguments: an integer and a pointer to
** an integer.  The first argument is 1, 0, or -1 to enable, disable, or
** leave unchanged the statement scanstatus option.  If the second argument
** is not NULL, then the value of the statement scanstatus setting after
** processing the first argument is written into the integer that the second
** argument points to.
** </dd>
**
** [[SQLITE_DBCONFIG_REVERSE_SCANORDER]]
** <dt>SQLITE_DBCONFIG_REVERSE_SCANORDER</dt>
** <dd>The SQLITE_DBCONFIG_REVERSE_SCANORDER option changes the default order
** in which tables and indexes are scanned so that the scans start at the end
** and work toward the beginning rather than starting at the beginning and
** working toward the end. Setting SQLITE_DBCONFIG_REVERSE_SCANORDER is the
** same as setting [PRAGMA reverse_unordered_selects]. <p>This option takes
** two arguments which are an integer and a pointer to an integer.  The first
** argument is 1, 0, or -1 to enable, disable, or leave unchanged the
** reverse scan order flag, respectively.  If the second argument is not NULL,
** then 0 or 1 is written into the integer that the second argument points to
** depending on if the reverse scan order flag is set after processing the
** first argument.
** </dd>
**
** [[SQLITE_DBCONFIG_ENABLE_ATTACH_CREATE]]
** <dt>SQLITE_DBCONFIG_ENABLE_ATTACH_CREATE</dt>
** <dd>The SQLITE_DBCONFIG_ENABLE_ATTACH_CREATE option enables or disables
** the ability of the [ATTACH DATABASE] SQL command to create a new database
** file if the database filed named in the ATTACH command does not already
** exist.  This ability of ATTACH to create a new database is enabled by
** default.  Applications can disable or reenable the ability for ATTACH to
** create new database files using this DBCONFIG option.<p>
** This option takes two arguments which are an integer and a pointer
** to an integer.  The first argument is 1, 0, or -1 to enable, disable, or
** leave unchanged the attach-create flag, respectively.  If the second
** argument is not NULL, then 0 or 1 is written into the integer that the
** second argument points to depending on if the attach-create flag is set
** after processing the first argument.
** </dd>
**
** [[SQLITE_DBCONFIG_ENABLE_ATTACH_WRITE]]
** <dt>SQLITE_DBCONFIG_ENABLE_ATTACH_WRITE</dt>
** <dd>The SQLITE_DBCONFIG_ENABLE_ATTACH_WRITE option enables or disables the
** ability of the [ATTACH DATABASE] SQL command to open a database for writing.
** This capability is enabled by default.  Applications can disable or
** reenable this capability using the current DBCONFIG option.  If
** this capability is disabled, the [ATTACH] command will still work,
** but the database will be opened read-only.  If this option is disabled,
** then the ability to create a new database using [ATTACH] is also disabled,
** regardless of the value of the [SQLITE_DBCONFIG_ENABLE_ATTACH_CREATE]
** option.<p>
** This option takes two arguments which are an integer and a pointer
** to an integer.  The first argument is 1, 0, or -1 to enable, disable, or
** leave unchanged the ability to ATTACH another database for writing,
** respectively.  If the second argument is not NULL, then 0 or 1 is written
** into the integer to which the second argument points, depending on whether
** the ability to ATTACH a read/write database is enabled or disabled
** after processing the first argument.
** </dd>
**
** [[SQLITE_DBCONFIG_ENABLE_COMMENTS]]
** <dt>SQLITE_DBCONFIG_ENABLE_COMMENTS</dt>
** <dd>The SQLITE_DBCONFIG_ENABLE_COMMENTS option enables or disables the
** ability to include comments in SQL text.  Comments are enabled by default.
** An application can disable or reenable comments in SQL text using this
** DBCONFIG option.<p>
** This option takes two arguments which are an integer and a pointer
** to an integer.  The first argument is 1, 0, or -1 to enable, disable, or
** leave unchanged the ability to use comments in SQL text,
** respectively.  If the second argument is not NULL, then 0 or 1 is written
** into the integer that the second argument points to depending on if
** comments are allowed in SQL text after processing the first argument.
** </dd>
**
** [[SQLITE_DBCONFIG_FP_DIGITS]]
** <dt>SQLITE_DBCONFIG_FP_DIGITS</dt>
** <dd>The SQLITE_DBCONFIG_FP_DIGITS setting is a small integer that determines
** the number of significant digits that SQLite will attempt to preserve when
** converting floating point numbers (IEEE 754 "doubles") into text.  The
** default value 17, as of SQLite version 3.52.0.  The value was 15 in all
** prior versions.<p>
** This option takes two arguments which are an integer and a pointer
** to an integer.  The first argument is a small integer, between 3 and 23, or
** zero.  The FP_DIGITS setting is changed to that small integer, or left
** unaltered if the first argument is zero or out of range. The second argument
** is a pointer to an integer.  If the pointer is not NULL, then the value of
** the FP_DIGITS setting, after possibly being modified by the first
** arguments, is written into the integer to which the second argument points.
** </dd>
**
** </dl>
**
** [[DBCONFIG arguments]] <h3>Arguments To SQLITE_DBCONFIG Options</h3>
**
** <p>Most of the SQLITE_DBCONFIG options take two arguments, so that the
** overall call to [sqlite3_db_config()] has a total of four parameters.
** The first argument (the third parameter to sqlite3_db_config()) is
** an integer.
** The second argument is a pointer to an integer. If the first argument is 1,
** then the option becomes enabled.  If the first integer argument is 0,
** then the option is disabled.
** If the first argument is -1, then the option setting
** is unchanged.  The second argument, the pointer to an integer, may be NULL.
** If the second argument is not NULL, then a value of 0 or 1 is written into
** the integer to which the second argument points, depending on whether the
** setting is disabled or enabled after applying any changes specified by
** the first argument.
**
** <p>While most SQLITE_DBCONFIG options use the argument format
** described in the previous paragraph, the [SQLITE_DBCONFIG_MAINDBNAME],
** [SQLITE_DBCONFIG_LOOKASIDE], and [SQLITE_DBCONFIG_FP_DIGITS] options
** are different.  See the documentation of those exceptional options for
** details.
*/
DBCONFIG_MAINDBNAME :: 1000 /* const char* */
DBCONFIG_LOOKASIDE :: 1001 /* void* int int */
DBCONFIG_ENABLE_FKEY :: 1002 /* int int* */
DBCONFIG_ENABLE_TRIGGER :: 1003 /* int int* */
DBCONFIG_ENABLE_FTS3_TOKENIZER :: 1004 /* int int* */
DBCONFIG_ENABLE_LOAD_EXTENSION :: 1005 /* int int* */
DBCONFIG_NO_CKPT_ON_CLOSE :: 1006 /* int int* */
DBCONFIG_ENABLE_QPSG :: 1007 /* int int* */
DBCONFIG_TRIGGER_EQP :: 1008 /* int int* */
DBCONFIG_RESET_DATABASE :: 1009 /* int int* */
DBCONFIG_DEFENSIVE :: 1010 /* int int* */
DBCONFIG_WRITABLE_SCHEMA :: 1011 /* int int* */
DBCONFIG_LEGACY_ALTER_TABLE :: 1012 /* int int* */
DBCONFIG_DQS_DML :: 1013 /* int int* */
DBCONFIG_DQS_DDL :: 1014 /* int int* */
DBCONFIG_ENABLE_VIEW :: 1015 /* int int* */
DBCONFIG_LEGACY_FILE_FORMAT :: 1016 /* int int* */
DBCONFIG_TRUSTED_SCHEMA :: 1017 /* int int* */
DBCONFIG_STMT_SCANSTATUS :: 1018 /* int int* */
DBCONFIG_REVERSE_SCANORDER :: 1019 /* int int* */
DBCONFIG_ENABLE_ATTACH_CREATE :: 1020 /* int int* */
DBCONFIG_ENABLE_ATTACH_WRITE :: 1021 /* int int* */
DBCONFIG_ENABLE_COMMENTS :: 1022 /* int int* */
DBCONFIG_FP_DIGITS :: 1023 /* int int* */
DBCONFIG_MAX :: 1023 /* Largest DBCONFIG */


/*
** CAPI3REF: Flags for sqlite3_setlk_timeout()
*/
SETLK_BLOCK_ON_CONNECT :: 0x01


/*
** CAPI3REF: Authorizer Return Codes
**
** The [sqlite3_set_authorizer | authorizer callback function] must
** return either [SQLITE_OK] or one of these two constants in order
** to signal SQLite whether or not the action is permitted.  See the
** [sqlite3_set_authorizer | authorizer documentation] for additional
** information.
**
** Note that SQLITE_IGNORE is also used as a [conflict resolution mode]
** returned from the [sqlite3_vtab_on_conflict()] interface.
*/
DENY :: 1 /* Abort the SQL statement with an error */
IGNORE :: 2 /* Don't allow access, but don't generate an error */

/*
** CAPI3REF: Authorizer Action Codes
**
** The [sqlite3_set_authorizer()] interface registers a callback function
** that is invoked to authorize certain SQL statement actions.  The
** second parameter to the callback is an integer code that specifies
** what action is being authorized.  These are the integer action codes that
** the authorizer callback may be passed.
**
** These action code values signify what kind of operation is to be
** authorized.  The 3rd and 4th parameters to the authorization
** callback function will be parameters or NULL depending on which of these
** codes is used as the second parameter.  ^(The 5th parameter to the
** authorizer callback is the name of the database ("main", "temp",
** etc.) if applicable.)^  ^The 6th parameter to the authorizer callback
** is the name of the inner-most trigger or view that is responsible for
** the access attempt or NULL if this access attempt is directly from
** top-level SQL code.
**
** The case of strings in the 3rd through the 6th argument to the
** authorization callback is arbitrary.  Authorization callbacks
** implementations should use [sqlite3_stricmp()] or similar when
** doing comparisons against those values.
*/
/******************************************* 3rd ************ 4th ***********/
CREATE_INDEX :: 1 /* Index Name      Table Name      */
CREATE_TABLE :: 2 /* Table Name      NULL            */
CREATE_TEMP_INDEX :: 3 /* Index Name      Table Name      */
CREATE_TEMP_TABLE :: 4 /* Table Name      NULL            */
CREATE_TEMP_TRIGGER :: 5 /* Trigger Name    Table Name      */
CREATE_TEMP_VIEW :: 6 /* View Name       NULL            */
CREATE_TRIGGER :: 7 /* Trigger Name    Table Name      */
CREATE_VIEW :: 8 /* View Name       NULL            */
DELETE :: 9 /* Table Name      NULL            */
DROP_INDEX :: 10 /* Index Name      Table Name      */
DROP_TABLE :: 11 /* Table Name      NULL            */
DROP_TEMP_INDEX :: 12 /* Index Name      Table Name      */
DROP_TEMP_TABLE :: 13 /* Table Name      NULL            */
DROP_TEMP_TRIGGER :: 14 /* Trigger Name    Table Name      */
DROP_TEMP_VIEW :: 15 /* View Name       NULL            */
DROP_TRIGGER :: 16 /* Trigger Name    Table Name      */
DROP_VIEW :: 17 /* View Name       NULL            */
INSERT :: 18 /* Table Name      NULL            */
PRAGMA :: 19 /* Pragma Name     1st arg or NULL */
READ :: 20 /* Table Name      Column Name     */
SELECT :: 21 /* NULL            NULL            */
TRANSACTION :: 22 /* Operation       NULL            */
UPDATE :: 23 /* Table Name      Column Name     */
ATTACH :: 24 /* Filename        NULL            */
DETACH :: 25 /* Database Name   NULL            */
ALTER_TABLE :: 26 /* Database Name   Table Name      */
REINDEX :: 27 /* Index Name      NULL            */
ANALYZE :: 28 /* Table Name      NULL            */
CREATE_VTABLE :: 29 /* Table Name      Module Name     */
DROP_VTABLE :: 30 /* Table Name      Module Name     */
FUNCTION :: 31 /* NULL            Function Name   */
SAVEPOINT :: 32 /* Operation       Savepoint Name  */
RECURSIVE :: 33 /* NULL            NULL            */


/*
** CAPI3REF: SQL Trace Event Codes
** KEYWORDS: SQLITE_TRACE
**
** These constants identify classes of events that can be monitored
** using the [sqlite3_trace_v2()] tracing logic.  The M argument
** to [sqlite3_trace_v2(D,M,X,P)] is an OR-ed combination of one or more of
** the following constants.  ^The first argument to the trace callback
** is one of the following constants.
**
** New tracing constants may be added in future releases.
**
** ^A trace callback has four arguments: xCallback(T,C,P,X).
** ^The T argument is one of the integer type codes above.
** ^The C argument is a copy of the context pointer passed in as the
** fourth argument to [sqlite3_trace_v2()].
** The P and X arguments are pointers whose meanings depend on T.
**
** <dl>
** [[SQLITE_TRACE_STMT]] <dt>SQLITE_TRACE_STMT</dt>
** <dd>^An SQLITE_TRACE_STMT callback is invoked when a prepared statement
** first begins running and possibly at other times during the
** execution of the prepared statement, such as at the start of each
** trigger subprogram. ^The P argument is a pointer to the
** [prepared statement]. ^The X argument is a pointer to a string which
** is the unexpanded SQL text of the prepared statement or an SQL comment
** that indicates the invocation of a trigger.  ^The callback can compute
** the same text that would have been returned by the legacy [sqlite3_trace()]
** interface by using the X argument when X begins with "--" and invoking
** [sqlite3_expanded_sql(P)] otherwise.
**
** [[SQLITE_TRACE_PROFILE]] <dt>SQLITE_TRACE_PROFILE</dt>
** <dd>^An SQLITE_TRACE_PROFILE callback provides approximately the same
** information as is provided by the [sqlite3_profile()] callback.
** ^The P argument is a pointer to the [prepared statement] and the
** X argument points to a 64-bit integer which is approximately
** the number of nanoseconds that the prepared statement took to run.
** ^The SQLITE_TRACE_PROFILE callback is invoked when the statement finishes.
**
** [[SQLITE_TRACE_ROW]] <dt>SQLITE_TRACE_ROW</dt>
** <dd>^An SQLITE_TRACE_ROW callback is invoked whenever a prepared
** statement generates a single row of result.
** ^The P argument is a pointer to the [prepared statement] and the
** X argument is unused.
**
** [[SQLITE_TRACE_CLOSE]] <dt>SQLITE_TRACE_CLOSE</dt>
** <dd>^An SQLITE_TRACE_CLOSE callback is invoked when a database
** connection closes.
** ^The P argument is a pointer to the [database connection] object
** and the X argument is unused.
** </dl>
*/
TRACE_STMT :: 0x01
TRACE_PROFILE :: 0x02
TRACE_ROW :: 0x04
TRACE_CLOSE :: 0x08


Stmt :: struct {}


/*
** CAPI3REF: Run-Time Limit Categories
** KEYWORDS: {limit category} {*limit categories}
**
** These constants define various performance limits
** that can be lowered at run-time using [sqlite3_limit()].
** A concise description of these limits follows, and additional information
** is available at [limits | Limits in SQLite].
**
** <dl>
** [[SQLITE_LIMIT_LENGTH]] ^(<dt>SQLITE_LIMIT_LENGTH</dt>
** <dd>The maximum size of any string or BLOB or table row, in bytes.<dd>)^
**
** [[SQLITE_LIMIT_SQL_LENGTH]] ^(<dt>SQLITE_LIMIT_SQL_LENGTH</dt>
** <dd>The maximum length of an SQL statement, in bytes.</dd>)^
**
** [[SQLITE_LIMIT_COLUMN]] ^(<dt>SQLITE_LIMIT_COLUMN</dt>
** <dd>The maximum number of columns in a table definition or in the
** result set of a [SELECT] or the maximum number of columns in an index
** or in an ORDER BY or GROUP BY clause.</dd>)^
**
** [[SQLITE_LIMIT_EXPR_DEPTH]] ^(<dt>SQLITE_LIMIT_EXPR_DEPTH</dt>
** <dd>The maximum depth of the parse tree on any expression and
** the maximum nesting depth for subqueries and VIEWs</dd>)^
**
** [[SQLITE_LIMIT_PARSER_DEPTH]] ^(<dt>SQLITE_LIMIT_PARSER_DEPTH</dt>
** <dd>The maximum depth of the LALR(1) parser stack used to analyze
** input SQL statements.</dd>)^
**
** [[SQLITE_LIMIT_COMPOUND_SELECT]] ^(<dt>SQLITE_LIMIT_COMPOUND_SELECT</dt>
** <dd>The maximum number of terms in a compound SELECT statement.</dd>)^
**
** [[SQLITE_LIMIT_VDBE_OP]] ^(<dt>SQLITE_LIMIT_VDBE_OP</dt>
** <dd>The maximum number of instructions in a virtual machine program
** used to implement an SQL statement.  If [sqlite3_prepare_v2()] or
** the equivalent tries to allocate space for more than this many opcodes
** in a single prepared statement, an SQLITE_NOMEM error is returned.</dd>)^
**
** [[SQLITE_LIMIT_FUNCTION_ARG]] ^(<dt>SQLITE_LIMIT_FUNCTION_ARG</dt>
** <dd>The maximum number of arguments on a function.</dd>)^
**
** [[SQLITE_LIMIT_ATTACHED]] ^(<dt>SQLITE_LIMIT_ATTACHED</dt>
** <dd>The maximum number of [ATTACH | attached databases].)^</dd>
**
** [[SQLITE_LIMIT_LIKE_PATTERN_LENGTH]]
** ^(<dt>SQLITE_LIMIT_LIKE_PATTERN_LENGTH</dt>
** <dd>The maximum length of the pattern argument to the [LIKE] or
** [GLOB] operators.</dd>)^
**
** [[SQLITE_LIMIT_VARIABLE_NUMBER]]
** ^(<dt>SQLITE_LIMIT_VARIABLE_NUMBER</dt>
** <dd>The maximum index number of any [parameter] in an SQL statement.)^
**
** [[SQLITE_LIMIT_TRIGGER_DEPTH]] ^(<dt>SQLITE_LIMIT_TRIGGER_DEPTH</dt>
** <dd>The maximum depth of recursion for triggers, and the maximum
** nesting depth for separate triggers.</dd>)^
**
** [[SQLITE_LIMIT_WORKER_THREADS]] ^(<dt>SQLITE_LIMIT_WORKER_THREADS</dt>
** <dd>The maximum number of auxiliary worker threads that a single
** [prepared statement] may start.</dd>)^
**
** [[SQLITE_LIMIT_SCHEMA]] ^(<dt>SQLITE_LIMIT_SCHEMA</dt>
** <dd>The maximum number of objects (tables, indexes, triggers, and views)
** defined by the database schema.</dd>)^
**
** [[SQLITE_LIMIT_TRIGGER_STEPS]] ^(<dt>SQLITE_LIMIT_TRIGGER_STEPS</dt>
** <dd>The maximum number of SQL statements that can be contained within
** a single trigger.</dd>)^
** </dl>
*/
LIMIT_LENGTH :: 0
LIMIT_SQL_LENGTH :: 1
LIMIT_COLUMN :: 2
LIMIT_EXPR_DEPTH :: 3
LIMIT_COMPOUND_SELECT :: 4
LIMIT_VDBE_OP :: 5
LIMIT_FUNCTION_ARG :: 6
LIMIT_ATTACHED :: 7
LIMIT_LIKE_PATTERN_LENGTH :: 8
LIMIT_VARIABLE_NUMBER :: 9
LIMIT_TRIGGER_DEPTH :: 10
LIMIT_WORKER_THREADS :: 11
LIMIT_PARSER_DEPTH :: 12
LIMIT_SCHEMA :: 13
LIMIT_TRIGGER_STEPS :: 14

/*
** CAPI3REF: Prepare Flags
**
** These constants define various flags that can be passed into the
** "prepFlags" parameter of the [sqlite3_prepare_v3()] and
** [sqlite3_prepare16_v3()] interfaces.
**
** New flags may be added in future releases of SQLite.
**
** <dl>
** [[SQLITE_PREPARE_PERSISTENT]] ^(<dt>SQLITE_PREPARE_PERSISTENT</dt>
** <dd>The SQLITE_PREPARE_PERSISTENT flag is a hint to the query planner
** that the prepared statement will be retained for a long time and
** probably reused many times.)^ ^Without this flag, [sqlite3_prepare_v3()]
** and [sqlite3_prepare16_v3()] assume that the prepared statement will
** be used just once or at most a few times and then destroyed using
** [sqlite3_finalize()] relatively soon. The current implementation acts
** on this hint by avoiding the use of [lookaside memory] so as not to
** deplete the limited store of lookaside memory. Future versions of
** SQLite may act on this hint differently.
**
** [[SQLITE_PREPARE_NORMALIZE]] <dt>SQLITE_PREPARE_NORMALIZE</dt>
** <dd>The SQLITE_PREPARE_NORMALIZE flag is a no-op. This flag used
** to be required for any prepared statement that wanted to use the
** [sqlite3_normalized_sql()] interface.  However, the
** [sqlite3_normalized_sql()] interface is now available to all
** prepared statements, regardless of whether or not they use this
** flag.
**
** [[SQLITE_PREPARE_NO_VTAB]] <dt>SQLITE_PREPARE_NO_VTAB</dt>
** <dd>The SQLITE_PREPARE_NO_VTAB flag causes the SQL compiler
** to return an error (error code SQLITE_ERROR) if the statement uses
** any virtual tables.
**
** [[SQLITE_PREPARE_DONT_LOG]] <dt>SQLITE_PREPARE_DONT_LOG</dt>
** <dd>The SQLITE_PREPARE_DONT_LOG flag prevents SQL compiler
** errors from being sent to the error log defined by
** [SQLITE_CONFIG_LOG].  This can be used, for example, to do test
** compiles to see if some SQL syntax is well-formed, without generating
** messages on the global error log when it is not.  If the test compile
** fails, the sqlite3_prepare_v3() call returns the same error indications
** with or without this flag; it just omits the call to [sqlite3_log()] that
** logs the error.
**
** [[SQLITE_PREPARE_FROM_DDL]] <dt>SQLITE_PREPARE_FROM_DDL</dt>
** <dd>The SQLITE_PREPARE_FROM_DDL flag causes the SQL compiler to enforce
** security constraints that would otherwise only be enforced when parsing
** the database schema.  In other words, the SQLITE_PREPARE_FROM_DDL flag
** causes the SQL compiler to treat the SQL statement being prepared as if
** it had come from an attacker.  When SQLITE_PREPARE_FROM_DDL is used and
** [SQLITE_DBCONFIG_TRUSTED_SCHEMA] is off, SQL functions may only be called
** if they are tagged with [SQLITE_INNOCUOUS] and virtual tables may only
** be used if they are tagged with [SQLITE_VTAB_INNOCUOUS].  Best practice
** is to use the SQLITE_PREPARE_FROM_DDL option when preparing any SQL that
** is derived from parts of the database schema. In particular, virtual
** table implementations that run SQL statements that are derived from
** arguments to their CREATE VIRTUAL TABLE statement should always use
** [sqlite3_prepare_v3()] and set the SQLITE_PREPARE_FROM_DDL flag to
** prevent bypass of the [SQLITE_DBCONFIG_TRUSTED_SCHEMA] security checks.
** </dl>
*/
PREPARE_PERSISTENT :: 0x01
PREPARE_NORMALIZE :: 0x02
PREPARE_NO_VTAB :: 0x04
PREPARE_DONT_LOG :: 0x10
PREPARE_FROM_DDL :: 0x20


Value :: struct {}
Context :: struct {}


/*
** CAPI3REF: Fundamental Datatypes
** KEYWORDS: SQLITE_TEXT
**
** ^(Every value in SQLite has one of five fundamental datatypes:
**
** <ul>
** <li> 64-bit signed integer
** <li> 64-bit IEEE floating point number
** <li> string
** <li> BLOB
** <li> NULL
** </ul>)^
**
** These constants are codes for each of those types.
**
** Note that the SQLITE_TEXT constant was also used in SQLite version 2
** for a completely different meaning.  Software that links against both
** SQLite version 2 and SQLite version 3 should use SQLITE3_TEXT, not
** SQLITE_TEXT.
*/
INTEGER :: 1
FLOAT :: 2
BLOB :: 4
NULL :: 5
TEXT :: 3
SQLITE3_TEXT :: 3


/*
** CAPI3REF: Text Encodings
**
** These constants define integer codes that represent the various
** text encodings supported by SQLite.
**
** <dl>
** [[SQLITE_UTF8]] <dt>SQLITE_UTF8</dt><dd>Text is encoding as UTF-8</dd>
**
** [[SQLITE_UTF16LE]] <dt>SQLITE_UTF16LE</dt><dd>Text is encoding as UTF-16
** with each code point being expressed "little endian" - the least significant
** byte first.  This is the usual encoding, for example on Windows.</dd>
**
** [[SQLITE_UTF16BE]] <dt>SQLITE_UTF16BE</dt><dd>Text is encoding as UTF-16
** with each code point being expressed "big endian" - the most significant
** byte first.  This encoding is less common, but is still sometimes seen,
** specially on older systems.
**
** [[SQLITE_UTF16]] <dt>SQLITE_UTF16</dt><dd>Text is encoding as UTF-16
** with each code point being expressed either little endian or as big
** endian, according to the native endianness of the host computer.
**
** [[SQLITE_ANY]] <dt>SQLITE_ANY</dt><dd>This encoding value may only be used
** to declare the preferred text for [application-defined SQL functions]
** created using [sqlite3_create_function()] and similar.  If the preferred
** encoding (the 4th parameter to sqlite3_create_function() - the eTextRep
** parameter) is SQLITE_ANY, that indicates that the function does not have
** a preference regarding the text encoding of its parameters and can take
** any text encoding that the SQLite core find convenient to supply.  This
** option is deprecated.  Please do not use it in new applications.
**
** [[SQLITE_UTF16_ALIGNED]] <dt>SQLITE_UTF16_ALIGNED</dt><dd>This encoding
** value may be used as the 3rd parameter (the eTextRep parameter) to
** [sqlite3_create_collation()] and similar.  This encoding value means
** that the application-defined collating sequence created expects its
** input strings to be in UTF16 in native byte order, and that the start
** of the strings must be aligned to a 2-byte boundary.
**
** [[SQLITE_UTF8_ZT]] <dt>SQLITE_UTF8_ZT</dt><dd>This option can only be
** used to specify the text encoding to strings input to
** [sqlite3_result_text64()] and [sqlite3_bind_text64()].
** The SQLITE_UTF8_ZT encoding means that the input string (call it "z")
** is UTF-8 encoded and that it is zero-terminated.  If the length parameter
** (call it "n") is non-negative, this encoding option means that the caller
** guarantees that z array contains at least n+1 bytes and that the z&#91;n&#93;
** byte has a value of zero.
** This option gives the same output as SQLITE_UTF8, but can be more efficient
** by avoiding the need to make a copy of the input string, in some cases.
** However, if z is allocated to hold fewer than n+1 bytes or if the
** z&#91;n&#93; byte is not zero, undefined behavior may result.
** </dl>
*/
UTF8 :: 1 /* IMP: R-37514-35566 */
UTF16LE :: 2 /* IMP: R-03371-37637 */
UTF16BE :: 3 /* IMP: R-51971-34154 */
UTF16 :: 4 /* Use native byte order */
ANY :: 5 /* Deprecated */
UTF16_ALIGNED :: 8 /* sqlite3_create_collation only */
UTF8_ZT :: 16 /* Zero-terminated UTF8 */

/*
** CAPI3REF: Function Flags
**
** These constants may be ORed together with the
** [SQLITE_UTF8 | preferred text encoding] as the fourth argument
** to [sqlite3_create_function()], [sqlite3_create_function16()], or
** [sqlite3_create_function_v2()].
**
** <dl>
** [[SQLITE_DETERMINISTIC]] <dt>SQLITE_DETERMINISTIC</dt><dd>
** The SQLITE_DETERMINISTIC flag means that the new function always gives
** the same output when the input parameters are the same.
** The [abs|abs() function] is deterministic, for example, but
** [randomblob|randomblob()] is not.  Functions must
** be deterministic in order to be used in certain contexts such as
** with the WHERE clause of [partial indexes] or in [generated columns].
** SQLite might also optimize deterministic functions by factoring them
** out of inner loops.
** </dd>
**
** [[SQLITE_DIRECTONLY]] <dt>SQLITE_DIRECTONLY</dt><dd>
** The SQLITE_DIRECTONLY flag means that the function may only be invoked
** from top-level SQL, and cannot be used in VIEWs or TRIGGERs nor in
** schema structures such as [CHECK constraints], [DEFAULT clauses],
** [expression indexes], [partial indexes], or [generated columns].
** <p>
** The SQLITE_DIRECTONLY flag is recommended for any
** [application-defined SQL function]
** that has side-effects or that could potentially leak sensitive information.
** This will prevent attacks in which an application is tricked
** into using a database file that has had its schema surreptitiously
** modified to invoke the application-defined function in ways that are
** harmful.
** <p>
** Some people say it is good practice to set SQLITE_DIRECTONLY on all
** [application-defined SQL functions], regardless of whether or not they
** are security sensitive, as doing so prevents those functions from being used
** inside of the database schema, and thus ensures that the database
** can be inspected and modified using generic tools (such as the [CLI])
** that do not have access to the application-defined functions.
** </dd>
**
** [[SQLITE_INNOCUOUS]] <dt>SQLITE_INNOCUOUS</dt><dd>
** The SQLITE_INNOCUOUS flag means that the function is unlikely
** to cause problems even if misused.  An innocuous function should have
** no side effects and should not depend on any values other than its
** input parameters. The [abs|abs() function] is an example of an
** innocuous function.
** The [load_extension() SQL function] is not innocuous because of its
** side effects.
** <p> SQLITE_INNOCUOUS is similar to SQLITE_DETERMINISTIC, but is not
** exactly the same.  The [random|random() function] is an example of a
** function that is innocuous but not deterministic.
** <p>Some heightened security settings
** ([SQLITE_DBCONFIG_TRUSTED_SCHEMA] and [PRAGMA trusted_schema=OFF])
** disable the use of SQL functions inside views and triggers and in
** schema structures such as [CHECK constraints], [DEFAULT clauses],
** [expression indexes], [partial indexes], and [generated columns] unless
** the function is tagged with SQLITE_INNOCUOUS.  Most built-in functions
** are innocuous.  Developers are advised to avoid using the
** SQLITE_INNOCUOUS flag for application-defined functions unless the
** function has been carefully audited and found to be free of potentially
** security-adverse side-effects and information-leaks.
** </dd>
**
** [[SQLITE_SUBTYPE]] <dt>SQLITE_SUBTYPE</dt><dd>
** The SQLITE_SUBTYPE flag indicates to SQLite that a function might call
** [sqlite3_value_subtype()] to inspect the sub-types of its arguments.
** This flag instructs SQLite to omit some corner-case optimizations that
** might disrupt the operation of the [sqlite3_value_subtype()] function,
** causing it to return zero rather than the correct subtype().
** All SQL functions that invoke [sqlite3_value_subtype()] should have this
** property.  If the SQLITE_SUBTYPE property is omitted, then the return
** value from [sqlite3_value_subtype()] might sometimes be zero even though
** a non-zero subtype was specified by the function argument expression.
**
** [[SQLITE_RESULT_SUBTYPE]] <dt>SQLITE_RESULT_SUBTYPE</dt><dd>
** The SQLITE_RESULT_SUBTYPE flag indicates to SQLite that a function might call
** [sqlite3_result_subtype()] to cause a sub-type to be associated with its
** result.
** Every function that invokes [sqlite3_result_subtype()] should have this
** property.  If it does not, then the call to [sqlite3_result_subtype()]
** might become a no-op if the function is used as a term in an
** [expression index].  On the other hand, SQL functions that never invoke
** [sqlite3_result_subtype()] should avoid setting this property, as the
** purpose of this property is to disable certain optimizations that are
** incompatible with subtypes.
**
** [[SQLITE_SELFORDER1]] <dt>SQLITE_SELFORDER1</dt><dd>
** The SQLITE_SELFORDER1 flag indicates that the function is an aggregate
** that internally orders the values provided to the first argument.  The
** ordered-set aggregate SQL notation with a single ORDER BY term can be
** used to invoke this function.  If the ordered-set aggregate notation is
** used on a function that lacks this flag, then an error is raised. Note
** that the ordered-set aggregate syntax is only available if SQLite is
** built using the -DSQLITE_ENABLE_ORDERED_SET_AGGREGATES compile-time option.
** </dd>
** </dl>
*/
DETERMINISTIC :: 0x000000800
DIRECTONLY :: 0x000080000
SUBTYPE :: 0x000100000
INNOCUOUS :: 0x000200000
RESULT_SUBTYPE :: 0x001000000
SELFORDER1 :: 0x002000000


/*
** CAPI3REF: Constants Defining Special Destructor Behavior
**
** These are special values for the destructor that is passed in as the
** final argument to routines like [sqlite3_result_blob()].  ^If the destructor
** argument is SQLITE_STATIC, it means that the content pointer is constant
** and will never change.  It does not need to be destroyed.  ^The
** SQLITE_TRANSIENT value means that the content will likely change in
** the near future and that SQLite should make its own private copy of
** the content before returning.
**
** The typedef is necessary to work around problems in certain
** C++ compilers.
*/
Destructor_Type :: proc "c" (_: rawptr)


/*
** CAPI3REF: Win32 Directory Types
**
** These macros are only available on Windows.  They define the allowed values
** for the type argument to the [sqlite3_win32_set_directory] interface.
*/
WIN32_DATA_DIRECTORY_TYPE :: 1
WIN32_TEMP_DIRECTORY_TYPE :: 2


/*
** CAPI3REF: Allowed return values from sqlite3_txn_state()
** KEYWORDS: {transaction state}
**
** These constants define the current transaction state of a database file.
** ^The [sqlite3_txn_state(D,S)] interface returns one of these
** constants in order to describe the transaction state of schema S
** in [database connection] D.
**
** <dl>
** [[SQLITE_TXN_NONE]] <dt>SQLITE_TXN_NONE</dt>
** <dd>The SQLITE_TXN_NONE state means that no transaction is currently
** pending.</dd>
**
** [[SQLITE_TXN_READ]] <dt>SQLITE_TXN_READ</dt>
** <dd>The SQLITE_TXN_READ state means that the database is currently
** in a read transaction.  Content has been read from the database file
** but nothing in the database file has changed.  The transaction state
** will be advanced to SQLITE_TXN_WRITE if any changes occur and there are
** no other conflicting concurrent write transactions.  The transaction
** state will revert to SQLITE_TXN_NONE following a [ROLLBACK] or
** [COMMIT].</dd>
**
** [[SQLITE_TXN_WRITE]] <dt>SQLITE_TXN_WRITE</dt>
** <dd>The SQLITE_TXN_WRITE state means that the database is currently
** in a write transaction.  Content has been written to the database file
** but has not yet committed.  The transaction state will change to
** SQLITE_TXN_NONE at the next [ROLLBACK] or [COMMIT].</dd>
*/
TXN_NONE :: 0
TXN_READ :: 1
TXN_WRITE :: 2


/*
** CAPI3REF: Virtual Table Object
** KEYWORDS: sqlite3_module {virtual table module}
**
** This structure, sometimes called a "virtual table module",
** defines the implementation of a [virtual table].
** This structure consists mostly of methods for the module.
**
** ^A virtual table module is created by filling in a persistent
** instance of this structure and passing a pointer to that instance
** to [sqlite3_create_module()] or [sqlite3_create_module_v2()].
** ^The registration remains valid until it is replaced by a different
** module or until the [database connection] closes.  The content
** of this structure must not change while it is registered with
** any database connection.
*/
Module :: struct {
	iVersion:      i32,
	xCreate:       proc "c" (_: ^Connection, pAux: rawptr, argc: i32, argv: [^]cstring, ppVTab: ^^Vtab, _: ^cstring) -> i32,
	xConnect:      proc "c" (_: ^Connection, pAux: rawptr, argc: i32, argv: [^]cstring, ppVTab: ^^Vtab, _: ^cstring) -> i32,
	xBestIndex:    proc "c" (pVTab: ^Vtab, _: ^Index_Info) -> i32,
	xDisconnect:   proc "c" (pVTab: ^Vtab) -> i32,
	xDestroy:      proc "c" (pVTab: ^Vtab) -> i32,
	xOpen:         proc "c" (pVTab: ^Vtab, ppCursor: ^^Vtab_Cursor) -> i32,
	xClose:        proc "c" (_: ^Vtab_Cursor) -> i32,
	xFilter:       proc "c" (_: ^Vtab_Cursor, idxNum: i32, idxStr: cstring, argc: i32, argv: [^]^Value) -> i32,
	xNext:         proc "c" (_: ^Vtab_Cursor) -> i32,
	xEof:          proc "c" (_: ^Vtab_Cursor) -> i32,
	xColumn:       proc "c" (_: ^Vtab_Cursor, _: ^Context, _: i32) -> i32,
	xRowid:        proc "c" (_: ^Vtab_Cursor, pRowid: ^i64) -> i32,
	xUpdate:       proc "c" (_: ^Vtab, _: i32, _: [^]^Value, _: ^i64) -> i32,
	xBegin:        proc "c" (pVTab: ^Vtab) -> i32,
	xSync:         proc "c" (pVTab: ^Vtab) -> i32,
	xCommit:       proc "c" (pVTab: ^Vtab) -> i32,
	xRollback:     proc "c" (pVTab: ^Vtab) -> i32,
	xFindFunction: proc "c" (pVtab: ^Vtab, nArg: i32, zName: cstring, pxFunc: ^proc "c" (_: ^Context, _: i32, _: [^]^Value), ppArg: ^rawptr) -> i32,
	xRename:       proc "c" (pVtab: ^Vtab, zNew: cstring) -> i32,

	/* The methods above are in version 1 of the sqlite_module object. Those
	** below are for version 2 and greater. */
	xSavepoint:    proc "c" (pVTab: ^Vtab, _: i32) -> i32,
	xRelease:      proc "c" (pVTab: ^Vtab, _: i32) -> i32,
	xRollbackTo:   proc "c" (pVTab: ^Vtab, _: i32) -> i32,

	/* The methods above are in versions 1 and 2 of the sqlite_module object.
	** Those below are for version 3 and greater. */
	xShadowName:   proc "c" (_: cstring) -> i32,

	/* The methods above are in versions 1 through 3 of the sqlite_module object.
	** Those below are for version 4 and greater. */
	xIntegrity:    proc "c" (pVTab: ^Vtab, zSchema: cstring, zTabName: cstring, mFlags: i32, pzErr: ^cstring) -> i32,
}

/*
** CAPI3REF: Virtual Table Indexing Information
** KEYWORDS: sqlite3_index_info
**
** The sqlite3_index_info structure and its substructures is used as part
** of the [virtual table] interface to
** pass information into and receive the reply from the [xBestIndex]
** method of a [virtual table module].  The fields under **Inputs** are the
** inputs to xBestIndex and are read-only.  xBestIndex inserts its
** results into the **Outputs** fields.
**
** ^(The aConstraint[] array records WHERE clause constraints of the form:
**
** <blockquote>column OP expr</blockquote>
**
** where OP is =, &lt;, &lt;=, &gt;, or &gt;=.)^  ^(The particular operator is
** stored in aConstraint[].op using one of the
** [SQLITE_INDEX_CONSTRAINT_EQ | SQLITE_INDEX_CONSTRAINT_ values].)^
** ^(The index of the column is stored in
** aConstraint[].iColumn.)^  ^(aConstraint[].usable is TRUE if the
** expr on the right-hand side can be evaluated (and thus the constraint
** is usable) and false if it cannot.)^
**
** ^The optimizer automatically inverts terms of the form "expr OP column"
** and makes other simplifications to the WHERE clause in an attempt to
** get as many WHERE clause terms into the form shown above as possible.
** ^The aConstraint[] array only reports WHERE clause terms that are
** relevant to the particular virtual table being queried.
**
** ^Information about the ORDER BY clause is stored in aOrderBy[].
** ^Each term of aOrderBy records a column of the ORDER BY clause.
**
** The colUsed field indicates which columns of the virtual table may be
** required by the current scan. Virtual table columns are numbered from
** zero in the order in which they appear within the CREATE TABLE statement
** passed to sqlite3_declare_vtab(). For the first 63 columns (columns 0-62),
** the corresponding bit is set within the colUsed mask if the column may be
** required by SQLite. If the table has at least 64 columns and any column
** to the right of the first 63 is required, then bit 63 of colUsed is also
** set. In other words, column iCol may be required if the expression
** (colUsed & ((sqlite3_uint64)1 << (iCol>=63 ? 63 : iCol))) evaluates to
** non-zero.
**
** The [xBestIndex] method must fill aConstraintUsage[] with information
** about what parameters to pass to xFilter.  ^If argvIndex>0 then
** the right-hand side of the corresponding aConstraint[] is evaluated
** and becomes the argvIndex-th entry in argv.  ^(If aConstraintUsage[].omit
** is true, then the constraint is assumed to be fully handled by the
** virtual table and might not be checked again by the byte code.)^ ^(The
** aConstraintUsage[].omit flag is an optimization hint. When the omit flag
** is left in its default setting of false, the constraint will always be
** checked separately in byte code.  If the omit flag is changed to true, then
** the constraint may or may not be checked in byte code.  In other words,
** when the omit flag is true there is no guarantee that the constraint will
** not be checked again using byte code.)^
**
** ^The idxNum and idxStr values are recorded and passed into the
** [xFilter] method.
** ^[sqlite3_free()] is used to free idxStr if and only if
** needToFreeIdxStr is true.
**
** ^The orderByConsumed means that output from [xFilter]/[xNext] will occur in
** the correct order to satisfy the ORDER BY clause so that no separate
** sorting step is required.
**
** ^The estimatedCost value is an estimate of the cost of a particular
** strategy. A cost of N indicates that the cost of the strategy is similar
** to a linear scan of an SQLite table with N rows. A cost of log(N)
** indicates that the expense of the operation is similar to that of a
** binary search on a unique indexed field of an SQLite table with N rows.
**
** ^The estimatedRows value is an estimate of the number of rows that
** will be returned by the strategy.
**
** The xBestIndex method may optionally populate the idxFlags field with a
** mask of SQLITE_INDEX_SCAN_* flags. One such flag is
** [SQLITE_INDEX_SCAN_HEX], which if set causes the [EXPLAIN QUERY PLAN]
** output to show the idxNum as hex instead of as decimal.  Another flag is
** SQLITE_INDEX_SCAN_UNIQUE, which if set indicates that the query plan will
** return at most one row.
**
** Additionally, if xBestIndex sets the SQLITE_INDEX_SCAN_UNIQUE flag, then
** SQLite also assumes that if a call to the xUpdate() method is made as
** part of the same statement to delete or update a virtual table row and the
** implementation returns SQLITE_CONSTRAINT, then there is no need to rollback
** any database changes. In other words, if the xUpdate() returns
** SQLITE_CONSTRAINT, the database contents must be exactly as they were
** before xUpdate was called. By contrast, if SQLITE_INDEX_SCAN_UNIQUE is not
** set and xUpdate returns SQLITE_CONSTRAINT, any database changes made by
** the xUpdate method are automatically rolled back by SQLite.
**
** IMPORTANT: The estimatedRows field was added to the sqlite3_index_info
** structure for SQLite [version 3.8.2] ([dateof:3.8.2]).
** If a virtual table extension is
** used with an SQLite version earlier than 3.8.2, the results of attempting
** to read or write the estimatedRows field are undefined (but are likely
** to include crashing the application). The estimatedRows field should
** therefore only be used if [sqlite3_libversion_number()] returns a
** value greater than or equal to 3008002. Similarly, the idxFlags field
** was added for [version 3.9.0] ([dateof:3.9.0]).
** It may therefore only be used if
** sqlite3_libversion_number() returns a value greater than or equal to
** 3009000.
*/
Index_Info :: struct {
	/* Inputs */
	nConstraint:      i32, /* Number of entries in aConstraint */
	aConstraint:      [^]Index_Constraint, /* Table of WHERE clause constraints */
	nOrderBy:         i32, /* Number of terms in the ORDER BY clause */
	aOrderBy:         [^]Index_Orderby, /* The ORDER BY clause */
	aConstraintUsage: [^]Index_Constraint_Usage,
	idxNum:           i32, /* Number used to identify the index */
	idxStr:           cstring, /* String, possibly obtained from sqlite3_malloc */
	needToFreeIdxStr: i32, /* Free idxStr using sqlite3_free() if true */
	orderByConsumed:  i32, /* True if output is already ordered */
	estimatedCost:    f64, /* Estimated cost of using this index */

	/* Fields below are only available in SQLite 3.8.2 and later */
	estimatedRows:    i64, /* Estimated number of rows returned */

	/* Fields below are only available in SQLite 3.9.0 and later */
	idxFlags:         i32, /* Mask of SQLITE_INDEX_SCAN_* flags */

	/* Fields below are only available in SQLite 3.10.0 and later */
	colUsed:          u64, /* Input: Mask of columns used by statement */
}

Index_Constraint :: struct {
	iColumn:     i32, /* Column constrained.  -1 for ROWID */
	op:          u8, /* Constraint operator */
	usable:      u8, /* True if this constraint is usable */
	iTermOffset: i32, /* Used internally - xBestIndex should ignore */
}

Index_Orderby :: struct {
	iColumn: i32, /* Column number */
	desc:    u8, /* True for DESC.  False for ASC. */
}

/* Outputs */
Index_Constraint_Usage :: struct {
	argvIndex: i32, /* if >0, constraint is part of argv to xFilter */
	omit:      u8, /* Do not code a test for this constraint */
}

/*
** CAPI3REF: Virtual Table Scan Flags
**
** Virtual table implementations are allowed to set the
** [sqlite3_index_info].idxFlags field to some combination of
** these bits.
*/
INDEX_SCAN_UNIQUE :: 0x00000001 /* Scan visits at most 1 row */
INDEX_SCAN_HEX :: 0x00000002 /* Display idxNum as hex */

/* in EXPLAIN QUERY PLAN */

/*
** CAPI3REF: Virtual Table Constraint Operator Codes
**
** These macros define the allowed values for the
** [sqlite3_index_info].aConstraint[].op field.  Each value represents
** an operator that is part of a constraint term in the WHERE clause of
** a query that uses a [virtual table].
**
** ^The left-hand operand of the operator is given by the corresponding
** aConstraint[].iColumn field.  ^An iColumn of -1 indicates the left-hand
** operand is the rowid.
** The SQLITE_INDEX_CONSTRAINT_LIMIT and SQLITE_INDEX_CONSTRAINT_OFFSET
** operators have no left-hand operand, and so for those operators the
** corresponding aConstraint[].iColumn is meaningless and should not be
** used.
**
** All operator values from SQLITE_INDEX_CONSTRAINT_FUNCTION through
** value 255 are reserved to represent functions that are overloaded
** by the [xFindFunction|xFindFunction method] of the virtual table
** implementation.
**
** The right-hand operands for each constraint might be accessible using
** the [sqlite3_vtab_rhs_value()] interface.  Usually the right-hand
** operand is only available if it appears as a single constant literal
** in the input SQL.  If the right-hand operand is another column or an
** expression (even a constant expression) or a parameter, then the
** sqlite3_vtab_rhs_value() probably will not be able to extract it.
** ^The SQLITE_INDEX_CONSTRAINT_ISNULL and
** SQLITE_INDEX_CONSTRAINT_ISNOTNULL operators have no right-hand operand
** and hence calls to sqlite3_vtab_rhs_value() for those operators will
** always return SQLITE_NOTFOUND.
**
** The collating sequence to be used for comparison can be found using
** the [sqlite3_vtab_collation()] interface.  For most real-world virtual
** tables, the collating sequence of constraints does not matter (for example
** because the constraints are numeric) and so the sqlite3_vtab_collation()
** interface is not commonly needed.
*/
INDEX_CONSTRAINT_EQ :: 2
INDEX_CONSTRAINT_GT :: 4
INDEX_CONSTRAINT_LE :: 8
INDEX_CONSTRAINT_LT :: 16
INDEX_CONSTRAINT_GE :: 32
INDEX_CONSTRAINT_MATCH :: 64
INDEX_CONSTRAINT_LIKE :: 65
INDEX_CONSTRAINT_GLOB :: 66
INDEX_CONSTRAINT_REGEXP :: 67
INDEX_CONSTRAINT_NE :: 68
INDEX_CONSTRAINT_ISNOT :: 69
INDEX_CONSTRAINT_ISNOTNULL :: 70
INDEX_CONSTRAINT_ISNULL :: 71
INDEX_CONSTRAINT_IS :: 72
INDEX_CONSTRAINT_LIMIT :: 73
INDEX_CONSTRAINT_OFFSET :: 74
INDEX_CONSTRAINT_FUNCTION :: 150


/*
** CAPI3REF: Virtual Table Instance Object
** KEYWORDS: sqlite3_vtab
**
** Every [virtual table module] implementation uses a subclass
** of this object to describe a particular instance
** of the [virtual table].  Each subclass will
** be tailored to the specific needs of the module implementation.
** The purpose of this superclass is to define certain fields that are
** common to all module implementations.
**
** ^Virtual tables methods can set an error message by assigning a
** string obtained from [sqlite3_mprintf()] to zErrMsg.  The method should
** take care that any prior string is freed by a call to [sqlite3_free()]
** prior to assigning a new string to zErrMsg.  ^After the error message
** is delivered up to the client application, the string will be automatically
** freed by sqlite3_free() and the zErrMsg field will be zeroed.
*/
Vtab :: struct {
	pModule: ^Module, /* The module for this virtual table */
	nRef:    i32, /* Number of open cursors */
	zErrMsg: cstring, /* Error message from sqlite3_mprintf() */
}

/*
** CAPI3REF: Virtual Table Cursor Object
** KEYWORDS: sqlite3_vtab_cursor {virtual table cursor}
**
** Every [virtual table module] implementation uses a subclass of the
** following structure to describe cursors that point into the
** [virtual table] and are used
** to loop through the virtual table.  Cursors are created using the
** [sqlite3_module.xOpen | xOpen] method of the module and are destroyed
** by the [sqlite3_module.xClose | xClose] method.  Cursors are used
** by the [xFilter], [xNext], [xEof], [xColumn], and [xRowid] methods
** of the module.  Each module implementation will define
** the content of a cursor structure to suit its own needs.
**
** This superclass exists in order to define fields of the cursor that
** are common to all implementations.
*/
Vtab_Cursor :: struct {
	pVtab: ^Vtab, /* Virtual table of this cursor */
}


Blob :: struct {}


Mutex_Methods :: struct {
	xMutexInit:    proc "c" () -> i32,
	xMutexEnd:     proc "c" () -> i32,
	xMutexAlloc:   proc "c" (_: i32) -> ^Mutex,
	xMutexFree:    proc "c" (_: ^Mutex),
	xMutexEnter:   proc "c" (_: ^Mutex),
	xMutexTry:     proc "c" (_: ^Mutex) -> i32,
	xMutexLeave:   proc "c" (_: ^Mutex),
	xMutexHeld:    proc "c" (_: ^Mutex) -> i32,
	xMutexNotheld: proc "c" (_: ^Mutex) -> i32,
}


/*
** CAPI3REF: Mutex Types
**
** The [sqlite3_mutex_alloc()] interface takes a single argument
** which is one of these integer constants.
**
** The set of static mutexes may change from one SQLite release to the
** next.  Applications that override the built-in mutex logic must be
** prepared to accommodate additional static mutexes.
*/
MUTEX_FAST :: 0
MUTEX_RECURSIVE :: 1
MUTEX_STATIC_MAIN :: 2
MUTEX_STATIC_MEM :: 3 /* sqlite3_malloc() */
MUTEX_STATIC_MEM2 :: 4 /* NOT USED */
MUTEX_STATIC_OPEN :: 4 /* sqlite3BtreeOpen() */
MUTEX_STATIC_PRNG :: 5 /* sqlite3_randomness() */
MUTEX_STATIC_LRU :: 6 /* lru page list */
MUTEX_STATIC_LRU2 :: 7 /* NOT USED */
MUTEX_STATIC_PMEM :: 7 /* sqlite3PageMalloc() */
MUTEX_STATIC_APP1 :: 8 /* For use by application */
MUTEX_STATIC_APP2 :: 9 /* For use by application */
MUTEX_STATIC_APP3 :: 10 /* For use by application */
MUTEX_STATIC_VFS1 :: 11 /* For use by built-in VFS */
MUTEX_STATIC_VFS2 :: 12 /* For use by extension VFS */
MUTEX_STATIC_VFS3 :: 13 /* For use by application VFS */

/* Legacy compatibility: */
MUTEX_STATIC_MASTER :: 2


/*
** CAPI3REF: Testing Interface Operation Codes
**
** These constants are the valid operation code parameters used
** as the first argument to [sqlite3_test_control()].
**
** These parameters and their meanings are subject to change
** without notice.  These values are for testing purposes only.
** Applications should not use any of these parameters or the
** [sqlite3_test_control()] interface.
*/
TESTCTRL_FIRST :: 5
TESTCTRL_PRNG_SAVE :: 5
TESTCTRL_PRNG_RESTORE :: 6
TESTCTRL_PRNG_RESET :: 7 /* NOT USED */
TESTCTRL_FK_NO_ACTION :: 7
TESTCTRL_BITVEC_TEST :: 8
TESTCTRL_FAULT_INSTALL :: 9
TESTCTRL_BENIGN_MALLOC_HOOKS :: 10
TESTCTRL_PENDING_BYTE :: 11
TESTCTRL_ASSERT :: 12
TESTCTRL_ALWAYS :: 13
TESTCTRL_RESERVE :: 14 /* NOT USED */
TESTCTRL_JSON_SELFCHECK :: 14
TESTCTRL_OPTIMIZATIONS :: 15
TESTCTRL_ISKEYWORD :: 16 /* NOT USED */
TESTCTRL_GETOPT :: 16
TESTCTRL_SCRATCHMALLOC :: 17 /* NOT USED */
TESTCTRL_INTERNAL_FUNCTIONS :: 17
TESTCTRL_LOCALTIME_FAULT :: 18
TESTCTRL_EXPLAIN_STMT :: 19 /* NOT USED */
TESTCTRL_ONCE_RESET_THRESHOLD :: 19
TESTCTRL_NEVER_CORRUPT :: 20
TESTCTRL_VDBE_COVERAGE :: 21
TESTCTRL_BYTEORDER :: 22
TESTCTRL_ISINIT :: 23
TESTCTRL_SORTER_MMAP :: 24
TESTCTRL_IMPOSTER :: 25
TESTCTRL_PARSER_COVERAGE :: 26
TESTCTRL_RESULT_INTREAL :: 27
TESTCTRL_PRNG_SEED :: 28
TESTCTRL_EXTRA_SCHEMA_CHECKS :: 29
TESTCTRL_SEEK_COUNT :: 30
TESTCTRL_TRACEFLAGS :: 31
TESTCTRL_TUNE :: 32
TESTCTRL_LOGEST :: 33
TESTCTRL_USELONGDOUBLE :: 34 /* NOT USED */
TESTCTRL_ATOF :: 34
TESTCTRL_LAST :: 34 /* Largest TESTCTRL */


Str :: struct {}


/*
** CAPI3REF: Control Flags For sqlite3_result_str()
**
** The following integers can be used as the third "F" argument
** to [sqlite3_result_str(C,S,F)].
*/
COPY :: 0 /* Results copied.  Dynamic string unchanged */
XFER :: 1 /* Results transfered.  Dynamic string reset */
FINISH :: 2 /* Like SQLITE_XFER, plus dynamic string freed */


/*
** CAPI3REF: Status Parameters
** KEYWORDS: {status parameters}
**
** These integer constants designate various run-time status parameters
** that can be returned by [sqlite3_status()].
**
** <dl>
** [[SQLITE_STATUS_MEMORY_USED]] ^(<dt>SQLITE_STATUS_MEMORY_USED</dt>
** <dd>This parameter is the current amount of memory checked out
** using [sqlite3_malloc()], either directly or indirectly.  The
** figure includes calls made to [sqlite3_malloc()] by the application
** and internal memory usage by the SQLite library.  Auxiliary page-cache
** memory controlled by [SQLITE_CONFIG_PAGECACHE] is not included in
** this parameter.  The amount returned is the sum of the allocation
** sizes as reported by the xSize method in [sqlite3_mem_methods].</dd>)^
**
** [[SQLITE_STATUS_MALLOC_SIZE]] ^(<dt>SQLITE_STATUS_MALLOC_SIZE</dt>
** <dd>This parameter records the largest memory allocation request
** handed to [sqlite3_malloc()] or [sqlite3_realloc()] (or their
** internal equivalents).  Only the value returned in the
** *pHighwater parameter to [sqlite3_status()] is of interest.
** The value written into the *pCurrent parameter is undefined.</dd>)^
**
** [[SQLITE_STATUS_MALLOC_COUNT]] ^(<dt>SQLITE_STATUS_MALLOC_COUNT</dt>
** <dd>This parameter records the number of separate memory allocations
** currently checked out.</dd>)^
**
** [[SQLITE_STATUS_PAGECACHE_USED]] ^(<dt>SQLITE_STATUS_PAGECACHE_USED</dt>
** <dd>This parameter returns the number of pages used out of the
** [pagecache memory allocator] that was configured using
** [SQLITE_CONFIG_PAGECACHE].  The
** value returned is in pages, not in bytes.</dd>)^
**
** [[SQLITE_STATUS_PAGECACHE_OVERFLOW]]
** ^(<dt>SQLITE_STATUS_PAGECACHE_OVERFLOW</dt>
** <dd>This parameter returns the number of bytes of page cache
** allocation which could not be satisfied by the [SQLITE_CONFIG_PAGECACHE]
** buffer and where forced to overflow to [sqlite3_malloc()].  The
** returned value includes allocations that overflowed because they
** were too large (they were larger than the "sz" parameter to
** [SQLITE_CONFIG_PAGECACHE]) and allocations that overflowed because
** no space was left in the page cache.</dd>)^
**
** [[SQLITE_STATUS_PAGECACHE_SIZE]] ^(<dt>SQLITE_STATUS_PAGECACHE_SIZE</dt>
** <dd>This parameter records the largest memory allocation request
** handed to the [pagecache memory allocator].  Only the value returned in the
** *pHighwater parameter to [sqlite3_status()] is of interest.
** The value written into the *pCurrent parameter is undefined.</dd>)^
**
** [[SQLITE_STATUS_SCRATCH_USED]] <dt>SQLITE_STATUS_SCRATCH_USED</dt>
** <dd>No longer used.</dd>
**
** [[SQLITE_STATUS_SCRATCH_OVERFLOW]] ^(<dt>SQLITE_STATUS_SCRATCH_OVERFLOW</dt>
** <dd>No longer used.</dd>
**
** [[SQLITE_STATUS_SCRATCH_SIZE]] <dt>SQLITE_STATUS_SCRATCH_SIZE</dt>
** <dd>No longer used.</dd>
**
** [[SQLITE_STATUS_PARSER_STACK]] ^(<dt>SQLITE_STATUS_PARSER_STACK</dt>
** <dd>The *pHighwater parameter records the deepest parser stack.
** The *pCurrent value is undefined.  The *pHighwater value is only
** meaningful if SQLite is compiled with [YYTRACKMAXSTACKDEPTH].</dd>)^
** </dl>
**
** New status parameters may be added from time to time.
*/
STATUS_MEMORY_USED :: 0
STATUS_PAGECACHE_USED :: 1
STATUS_PAGECACHE_OVERFLOW :: 2
STATUS_SCRATCH_USED :: 3 /* NOT USED */
STATUS_SCRATCH_OVERFLOW :: 4 /* NOT USED */
STATUS_MALLOC_SIZE :: 5
STATUS_PARSER_STACK :: 6
STATUS_PAGECACHE_SIZE :: 7
STATUS_SCRATCH_SIZE :: 8 /* NOT USED */
STATUS_MALLOC_COUNT :: 9


/*
** CAPI3REF: Status Parameters for database connections
** KEYWORDS: {SQLITE_DBSTATUS options}
**
** These constants are the available integer "verbs" that can be passed as
** the second argument to the [sqlite3_db_status()] interface.
**
** New verbs may be added in future releases of SQLite. Existing verbs
** might be discontinued. Applications should check the return code from
** [sqlite3_db_status()] to make sure that the call worked.
** The [sqlite3_db_status()] interface will return a non-zero error code
** if a discontinued or unsupported verb is invoked.
**
** <dl>
** [[SQLITE_DBSTATUS_LOOKASIDE_USED]] ^(<dt>SQLITE_DBSTATUS_LOOKASIDE_USED</dt>
** <dd>This parameter returns the number of lookaside memory slots currently
** checked out.</dd>)^
**
** [[SQLITE_DBSTATUS_LOOKASIDE_HIT]] ^(<dt>SQLITE_DBSTATUS_LOOKASIDE_HIT</dt>
** <dd>This parameter returns the number of malloc attempts that were
** satisfied using lookaside memory. Only the high-water value is meaningful;
** the current value is always zero.</dd>)^
**
** [[SQLITE_DBSTATUS_LOOKASIDE_MISS_SIZE]]
** ^(<dt>SQLITE_DBSTATUS_LOOKASIDE_MISS_SIZE</dt>
** <dd>This parameter returns the number of malloc attempts that might have
** been satisfied using lookaside memory but failed due to the amount of
** memory requested being larger than the lookaside slot size.
** Only the high-water value is meaningful;
** the current value is always zero.</dd>)^
**
** [[SQLITE_DBSTATUS_LOOKASIDE_MISS_FULL]]
** ^(<dt>SQLITE_DBSTATUS_LOOKASIDE_MISS_FULL</dt>
** <dd>This parameter returns the number of malloc attempts that might have
** been satisfied using lookaside memory but failed due to all lookaside
** memory already being in use.
** Only the high-water value is meaningful;
** the current value is always zero.</dd>)^
**
** [[SQLITE_DBSTATUS_CACHE_USED]] ^(<dt>SQLITE_DBSTATUS_CACHE_USED</dt>
** <dd>This parameter returns the approximate number of bytes of heap
** memory used by all pager caches associated with the database connection.)^
** ^The highwater mark associated with SQLITE_DBSTATUS_CACHE_USED is always 0.
** </dd>
**
** [[SQLITE_DBSTATUS_CACHE_USED_SHARED]]
** ^(<dt>SQLITE_DBSTATUS_CACHE_USED_SHARED</dt>
** <dd>This parameter is similar to DBSTATUS_CACHE_USED, except that if a
** pager cache is shared between two or more connections the bytes of heap
** memory used by that pager cache is divided evenly between the attached
** connections.)^  In other words, if none of the pager caches associated
** with the database connection are shared, this request returns the same
** value as DBSTATUS_CACHE_USED. Or, if one or more of the pager caches are
** shared, the value returned by this call will be smaller than that returned
** by DBSTATUS_CACHE_USED. ^The highwater mark associated with
** SQLITE_DBSTATUS_CACHE_USED_SHARED is always 0.</dd>
**
** [[SQLITE_DBSTATUS_SCHEMA_USED]] ^(<dt>SQLITE_DBSTATUS_SCHEMA_USED</dt>
** <dd>This parameter returns the approximate number of bytes of heap
** memory used to store the schema for all databases associated
** with the connection - main, temp, and any [ATTACH]-ed databases.)^
** ^The full amount of memory used by the schemas is reported, even if the
** schema memory is shared with other database connections due to
** [shared cache mode] being enabled.
** ^The highwater mark associated with SQLITE_DBSTATUS_SCHEMA_USED is always 0.
** </dd>
**
** [[SQLITE_DBSTATUS_STMT_USED]] ^(<dt>SQLITE_DBSTATUS_STMT_USED</dt>
** <dd>This parameter returns the approximate number of bytes of heap
** and lookaside memory used by all prepared statements associated with
** the database connection.)^
** ^The highwater mark associated with SQLITE_DBSTATUS_STMT_USED is always 0.
** </dd>
**
** [[SQLITE_DBSTATUS_CACHE_HIT]] ^(<dt>SQLITE_DBSTATUS_CACHE_HIT</dt>
** <dd>This parameter returns the number of pager cache hits that have
** occurred.)^ ^The highwater mark associated with SQLITE_DBSTATUS_CACHE_HIT
** is always 0.
** </dd>
**
** [[SQLITE_DBSTATUS_CACHE_MISS]] ^(<dt>SQLITE_DBSTATUS_CACHE_MISS</dt>
** <dd>This parameter returns the number of pager cache misses that have
** occurred.)^ ^The highwater mark associated with SQLITE_DBSTATUS_CACHE_MISS
** is always 0.
** </dd>
**
** [[SQLITE_DBSTATUS_CACHE_WRITE]] ^(<dt>SQLITE_DBSTATUS_CACHE_WRITE</dt>
** <dd>This parameter returns the number of dirty cache entries that have
** been written to disk. Specifically, the number of pages written to the
** wal file in wal mode databases, or the number of pages written to the
** database file in rollback mode databases. Any pages written as part of
** transaction rollback or database recovery operations are not included.
** If an IO or other error occurs while writing a page to disk, the effect
** on subsequent SQLITE_DBSTATUS_CACHE_WRITE requests is undefined.)^ ^The
** highwater mark associated with SQLITE_DBSTATUS_CACHE_WRITE is always 0.
** <p>
** ^(There is overlap between the quantities measured by this parameter
** (SQLITE_DBSTATUS_CACHE_WRITE) and SQLITE_DBSTATUS_TEMPBUF_SPILL.
** Resetting one will reduce the other.)^
** </dd>
**
** [[SQLITE_DBSTATUS_CACHE_SPILL]] ^(<dt>SQLITE_DBSTATUS_CACHE_SPILL</dt>
** <dd>This parameter returns the number of dirty cache entries that have
** been written to disk in the middle of a transaction due to the page
** cache overflowing. Transactions are more efficient if they are written
** to disk all at once. When pages spill mid-transaction, that introduces
** additional overhead. This parameter can be used to help identify
** inefficiencies that can be resolved by increasing the cache size.
** </dd>
**
** [[SQLITE_DBSTATUS_DEFERRED_FKS]] ^(<dt>SQLITE_DBSTATUS_DEFERRED_FKS</dt>
** <dd>This parameter returns zero for the current value if and only if
** all foreign key constraints (deferred or immediate) have been
** resolved.)^  ^The highwater mark is always 0.
**
** [[SQLITE_DBSTATUS_TEMPBUF_SPILL] ^(<dt>SQLITE_DBSTATUS_TEMPBUF_SPILL</dt>
** <dd>^(This parameter returns the number of bytes written to temporary
** files on disk that could have been kept in memory had sufficient memory
** been available.  This value includes writes to intermediate tables that
** are part of complex queries, external sorts that spill to disk, and
** writes to TEMP tables.)^
** ^The highwater mark is always 0.
** <p>
** ^(There is overlap between the quantities measured by this parameter
** (SQLITE_DBSTATUS_TEMPBUF_SPILL) and SQLITE_DBSTATUS_CACHE_WRITE.
** Resetting one will reduce the other.)^
** </dd>
** </dl>
*/
DBSTATUS_LOOKASIDE_USED :: 0
DBSTATUS_CACHE_USED :: 1
DBSTATUS_SCHEMA_USED :: 2
DBSTATUS_STMT_USED :: 3
DBSTATUS_LOOKASIDE_HIT :: 4
DBSTATUS_LOOKASIDE_MISS_SIZE :: 5
DBSTATUS_LOOKASIDE_MISS_FULL :: 6
DBSTATUS_CACHE_HIT :: 7
DBSTATUS_CACHE_MISS :: 8
DBSTATUS_CACHE_WRITE :: 9
DBSTATUS_DEFERRED_FKS :: 10
DBSTATUS_CACHE_USED_SHARED :: 11
DBSTATUS_CACHE_SPILL :: 12
DBSTATUS_TEMPBUF_SPILL :: 13
DBSTATUS_MAX :: 13 /* Largest defined DBSTATUS */


/*
** CAPI3REF: Status Parameters for prepared statements
** KEYWORDS: {SQLITE_STMTSTATUS counter} {SQLITE_STMTSTATUS counters}
**
** These preprocessor macros define integer codes that name counter
** values associated with the [sqlite3_stmt_status()] interface.
** The meanings of the various counters are as follows:
**
** <dl>
** [[SQLITE_STMTSTATUS_FULLSCAN_STEP]] <dt>SQLITE_STMTSTATUS_FULLSCAN_STEP</dt>
** <dd>^This is the number of times that SQLite has stepped forward in
** a table as part of a full table scan.  Large numbers for this counter
** may indicate opportunities for performance improvement through
** careful use of indices.</dd>
**
** [[SQLITE_STMTSTATUS_SORT]] <dt>SQLITE_STMTSTATUS_SORT</dt>
** <dd>^This is the number of sort operations that have occurred.
** A non-zero value in this counter may indicate an opportunity to
** improve performance through careful use of indices.</dd>
**
** [[SQLITE_STMTSTATUS_AUTOINDEX]] <dt>SQLITE_STMTSTATUS_AUTOINDEX</dt>
** <dd>^This is the number of rows inserted into transient indices that
** were created automatically in order to help joins run faster.
** A non-zero value in this counter may indicate an opportunity to
** improve performance by adding permanent indices that do not
** need to be reinitialized each time the statement is run.</dd>
**
** [[SQLITE_STMTSTATUS_VM_STEP]] <dt>SQLITE_STMTSTATUS_VM_STEP</dt>
** <dd>^This is the number of virtual machine operations executed
** by the prepared statement if that number is less than or equal
** to 2147483647.  The number of virtual machine operations can be
** used as a proxy for the total work done by the prepared statement.
** If the number of virtual machine operations exceeds 2147483647
** then the value returned by this statement status code is undefined.</dd>
**
** [[SQLITE_STMTSTATUS_REPREPARE]] <dt>SQLITE_STMTSTATUS_REPREPARE</dt>
** <dd>^This is the number of times that the prepare statement has been
** automatically regenerated due to schema changes or changes to
** [bound parameters] that might affect the query plan.</dd>
**
** [[SQLITE_STMTSTATUS_RUN]] <dt>SQLITE_STMTSTATUS_RUN</dt>
** <dd>^This is the number of times that the prepared statement has
** been run.  A single "run" for the purposes of this counter is one
** or more calls to [sqlite3_step()] followed by a call to [sqlite3_reset()].
** The counter is incremented on the first [sqlite3_step()] call of each
** cycle.</dd>
**
** [[SQLITE_STMTSTATUS_FILTER_MISS]]
** [[SQLITE_STMTSTATUS_FILTER HIT]]
** <dt>SQLITE_STMTSTATUS_FILTER_HIT<br>
** SQLITE_STMTSTATUS_FILTER_MISS</dt>
** <dd>^SQLITE_STMTSTATUS_FILTER_HIT is the number of times that a join
** step was bypassed because a Bloom filter returned not-found.  The
** corresponding SQLITE_STMTSTATUS_FILTER_MISS value is the number of
** times that the Bloom filter returned a find, and thus the join step
** had to be processed as normal.</dd>
**
** [[SQLITE_STMTSTATUS_MEMUSED]] <dt>SQLITE_STMTSTATUS_MEMUSED</dt>
** <dd>^This is the approximate number of bytes of heap memory
** used to store the prepared statement.  ^This value is not actually
** a counter, and so the resetFlg parameter to sqlite3_stmt_status()
** is ignored when the opcode is SQLITE_STMTSTATUS_MEMUSED.
** </dd>
** </dl>
*/
STMTSTATUS_FULLSCAN_STEP :: 1
STMTSTATUS_SORT :: 2
STMTSTATUS_AUTOINDEX :: 3
STMTSTATUS_VM_STEP :: 4
STMTSTATUS_REPREPARE :: 5
STMTSTATUS_RUN :: 6
STMTSTATUS_FILTER_MISS :: 7
STMTSTATUS_FILTER_HIT :: 8
STMTSTATUS_MEMUSED :: 99

Pcache :: struct {}

Pcache_Page :: struct {
	pBuf:   rawptr, /* The content of the page */
	pExtra: rawptr, /* Extra information associated with the page */
}

Pcache_Methods2 :: struct {
	iVersion:   i32,
	pArg:       rawptr,
	xInit:      proc "c" (_: rawptr) -> i32,
	xShutdown:  proc "c" (_: rawptr),
	xCreate:    proc "c" (szPage: i32, szExtra: i32, bPurgeable: i32) -> ^Pcache,
	xCachesize: proc "c" (_: ^Pcache, nCachesize: i32),
	xPagecount: proc "c" (_: ^Pcache) -> i32,
	xFetch:     proc "c" (_: ^Pcache, key: u32, createFlag: i32) -> ^Pcache_Page,
	xUnpin:     proc "c" (_: ^Pcache, _: ^Pcache_Page, discard: i32),
	xRekey:     proc "c" (_: ^Pcache, _: ^Pcache_Page, oldKey: u32, newKey: u32),
	xTruncate:  proc "c" (_: ^Pcache, iLimit: u32),
	xDestroy:   proc "c" (_: ^Pcache),
	xShrink:    proc "c" (_: ^Pcache),
}

Pcache_Methods :: struct {
	pArg:       rawptr,
	xInit:      proc "c" (_: rawptr) -> i32,
	xShutdown:  proc "c" (_: rawptr),
	xCreate:    proc "c" (szPage: i32, bPurgeable: i32) -> ^Pcache,
	xCachesize: proc "c" (_: ^Pcache, nCachesize: i32),
	xPagecount: proc "c" (_: ^Pcache) -> i32,
	xFetch:     proc "c" (_: ^Pcache, key: u32, createFlag: i32) -> rawptr,
	xUnpin:     proc "c" (_: ^Pcache, _: rawptr, discard: i32),
	xRekey:     proc "c" (_: ^Pcache, _: rawptr, oldKey: u32, newKey: u32),
	xTruncate:  proc "c" (_: ^Pcache, iLimit: u32),
	xDestroy:   proc "c" (_: ^Pcache),
}

Backup :: struct {}


/*
** CAPI3REF: Checkpoint Mode Values
** KEYWORDS: {checkpoint mode}
**
** These constants define all valid values for the "checkpoint mode" passed
** as the third parameter to the [sqlite3_wal_checkpoint_v2()] interface.
** See the [sqlite3_wal_checkpoint_v2()] documentation for details on the
** meaning of each of these checkpoint modes.
*/
CHECKPOINT_NOOP :: -1 /* Do no work at all */
CHECKPOINT_PASSIVE :: 0 /* Do as much as possible w/o blocking */
CHECKPOINT_FULL :: 1 /* Wait for writers, then checkpoint */
CHECKPOINT_RESTART :: 2 /* Like FULL but wait for readers */
CHECKPOINT_TRUNCATE :: 3 /* Like RESTART but also truncate WAL */


/*
** CAPI3REF: Virtual Table Configuration Options
** KEYWORDS: {virtual table configuration options}
** KEYWORDS: {virtual table configuration option}
**
** These macros define the various options to the
** [sqlite3_vtab_config()] interface that [virtual table] implementations
** can use to customize and optimize their behavior.
**
** <dl>
** [[SQLITE_VTAB_CONSTRAINT_SUPPORT]]
** <dt>SQLITE_VTAB_CONSTRAINT_SUPPORT</dt>
** <dd>Calls of the form
** [sqlite3_vtab_config](db,SQLITE_VTAB_CONSTRAINT_SUPPORT,X) are supported,
** where X is an integer.  If X is zero, then the [virtual table] whose
** [xCreate] or [xConnect] method invoked [sqlite3_vtab_config()] does not
** support constraints.  In this configuration (which is the default) if
** a call to the [xUpdate] method returns [SQLITE_CONSTRAINT], then the entire
** statement is rolled back as if [ON CONFLICT | OR ABORT] had been
** specified as part of the user's SQL statement, regardless of the actual
** ON CONFLICT mode specified.
**
** If X is non-zero, then the virtual table implementation guarantees
** that if [xUpdate] returns [SQLITE_CONSTRAINT], it will do so before
** any modifications to internal or persistent data structures have been made.
** If the [ON CONFLICT] mode is ABORT, FAIL, IGNORE or ROLLBACK, SQLite
** is able to roll back a statement or database transaction, and abandon
** or continue processing the current SQL statement as appropriate.
** If the ON CONFLICT mode is REPLACE and the [xUpdate] method returns
** [SQLITE_CONSTRAINT], SQLite handles this as if the ON CONFLICT mode
** had been ABORT.
**
** Virtual table implementations that are required to handle OR REPLACE
** must do so within the [xUpdate] method. If a call to the
** [sqlite3_vtab_on_conflict()] function indicates that the current ON
** CONFLICT policy is REPLACE, the virtual table implementation should
** silently replace the appropriate rows within the xUpdate callback and
** return SQLITE_OK. Or, if this is not possible, it may return
** SQLITE_CONSTRAINT, in which case SQLite falls back to OR ABORT
** constraint handling.
** </dd>
**
** [[SQLITE_VTAB_DIRECTONLY]]<dt>SQLITE_VTAB_DIRECTONLY</dt>
** <dd>Calls of the form
** [sqlite3_vtab_config](db,SQLITE_VTAB_DIRECTONLY) from within the
** the [xConnect] or [xCreate] methods of a [virtual table] implementation
** prohibits that virtual table from being used from within triggers and
** views.
** </dd>
**
** [[SQLITE_VTAB_INNOCUOUS]]<dt>SQLITE_VTAB_INNOCUOUS</dt>
** <dd>Calls of the form
** [sqlite3_vtab_config](db,SQLITE_VTAB_INNOCUOUS) from within the
** [xConnect] or [xCreate] methods of a [virtual table] implementation
** identify that virtual table as being safe to use from within triggers
** and views.  Conceptually, the SQLITE_VTAB_INNOCUOUS tag means that the
** virtual table can do no serious harm even if it is controlled by a
** malicious hacker.  Developers should avoid setting the SQLITE_VTAB_INNOCUOUS
** flag unless absolutely necessary.
** </dd>
**
** [[SQLITE_VTAB_USES_ALL_SCHEMAS]]<dt>SQLITE_VTAB_USES_ALL_SCHEMAS</dt>
** <dd>Calls of the form
** [sqlite3_vtab_config](db,SQLITE_VTAB_USES_ALL_SCHEMA) from within the
** the [xConnect] or [xCreate] methods of a [virtual table] implementation
** instruct the query planner to begin at least a read transaction on
** all schemas ("main", "temp", and any ATTACH-ed databases) whenever the
** virtual table is used.
** </dd>
** </dl>
*/
VTAB_CONSTRAINT_SUPPORT :: 1
VTAB_INNOCUOUS :: 2
VTAB_DIRECTONLY :: 3
VTAB_USES_ALL_SCHEMAS :: 4


/*
** CAPI3REF: Conflict resolution modes
** KEYWORDS: {conflict resolution mode}
**
** These constants are returned by [sqlite3_vtab_on_conflict()] to
** inform a [virtual table] implementation of the [ON CONFLICT] mode
** for the SQL statement being evaluated.
**
** Note that the [SQLITE_IGNORE] constant is also used as a potential
** return value from the [sqlite3_set_authorizer()] callback and that
** [SQLITE_ABORT] is also a [result code].
*/
ROLLBACK :: 1

/* #define SQLITE_IGNORE 2 // Also used by sqlite3_authorizer() callback */
FAIL :: 3

/* #define SQLITE_ABORT 4  // Also an error code */
REPLACE :: 5

/*
** CAPI3REF: Prepared Statement Scan Status Opcodes
** KEYWORDS: {scanstatus options}
**
** The following constants can be used for the T parameter to the
** [sqlite3_stmt_scanstatus(S,X,T,V)] interface.  Each constant designates a
** different metric for sqlite3_stmt_scanstatus() to return.
**
** When the value returned to V is a string, space to hold that string is
** managed by the prepared statement S and will be automatically freed when
** S is finalized.
**
** Not all values are available for all query elements. When a value is
** not available, the output variable is set to -1 if the value is numeric,
** or to NULL if it is a string (SQLITE_SCANSTAT_NAME).
**
** <dl>
** [[SQLITE_SCANSTAT_NLOOP]] <dt>SQLITE_SCANSTAT_NLOOP</dt>
** <dd>^The [sqlite3_int64] variable pointed to by the V parameter will be
** set to the total number of times that the X-th loop has run.</dd>
**
** [[SQLITE_SCANSTAT_NVISIT]] <dt>SQLITE_SCANSTAT_NVISIT</dt>
** <dd>^The [sqlite3_int64] variable pointed to by the V parameter will be set
** to the total number of rows examined by all iterations of the X-th loop.</dd>
**
** [[SQLITE_SCANSTAT_EST]] <dt>SQLITE_SCANSTAT_EST</dt>
** <dd>^The "double" variable pointed to by the V parameter will be set to the
** query planner's estimate for the average number of rows output from each
** iteration of the X-th loop.  If the query planner's estimate was accurate,
** then this value will approximate the quotient NVISIT/NLOOP and the
** product of this value for all prior loops with the same SELECTID will
** be the NLOOP value for the current loop.</dd>
**
** [[SQLITE_SCANSTAT_NAME]] <dt>SQLITE_SCANSTAT_NAME</dt>
** <dd>^The "const char *" variable pointed to by the V parameter will be set
** to a zero-terminated UTF-8 string containing the name of the index or table
** used for the X-th loop.</dd>
**
** [[SQLITE_SCANSTAT_EXPLAIN]] <dt>SQLITE_SCANSTAT_EXPLAIN</dt>
** <dd>^The "const char *" variable pointed to by the V parameter will be set
** to a zero-terminated UTF-8 string containing the [EXPLAIN QUERY PLAN]
** description for the X-th loop.</dd>
**
** [[SQLITE_SCANSTAT_SELECTID]] <dt>SQLITE_SCANSTAT_SELECTID</dt>
** <dd>^The "int" variable pointed to by the V parameter will be set to the
** id for the X-th query plan element. The id value is unique within the
** statement. The select-id is the same value as is output in the first
** column of an [EXPLAIN QUERY PLAN] query.</dd>
**
** [[SQLITE_SCANSTAT_PARENTID]] <dt>SQLITE_SCANSTAT_PARENTID</dt>
** <dd>The "int" variable pointed to by the V parameter will be set to the
** id of the parent of the current query element, if applicable, or
** to zero if the query element has no parent. This is the same value as
** returned in the second column of an [EXPLAIN QUERY PLAN] query.</dd>
**
** [[SQLITE_SCANSTAT_NCYCLE]] <dt>SQLITE_SCANSTAT_NCYCLE</dt>
** <dd>The sqlite3_int64 output value is set to the number of cycles,
** according to the processor time-stamp counter, that elapsed while the
** query element was being processed. This value is not available for
** all query elements - if it is unavailable the output variable is
** set to -1.</dd>
** </dl>
*/
SCANSTAT_NLOOP :: 0
SCANSTAT_NVISIT :: 1
SCANSTAT_EST :: 2
SCANSTAT_NAME :: 3
SCANSTAT_EXPLAIN :: 4
SCANSTAT_SELECTID :: 5
SCANSTAT_PARENTID :: 6
SCANSTAT_NCYCLE :: 7


/*
** CAPI3REF: Prepared Statement Scan Status
** KEYWORDS: {scan status flags}
*/
SCANSTAT_COMPLEX :: 0x0001


/*
** CAPI3REF: Database Snapshot
** KEYWORDS: {snapshot} {sqlite3_snapshot}
**
** An instance of the snapshot object records the state of a [WAL mode]
** database for some specific point in history.
**
** In [WAL mode], multiple [database connections] that are open on the
** same database file can each be reading a different historical version
** of the database file.  When a [database connection] begins a read
** transaction, that connection sees an unchanging copy of the database
** as it existed for the point in time when the transaction first started.
** Subsequent changes to the database from other connections are not seen
** by the reader until a new read transaction is started.
**
** The sqlite3_snapshot object records state information about an historical
** version of the database file so that it is possible to later open a new read
** transaction that sees that historical version of the database rather than
** the most recent version.
*/
Snapshot :: struct {
	hidden: [48]u8,
}


/*
** CAPI3REF: Flags for sqlite3_serialize
**
** Zero or more of the following constants can be OR-ed together for
** the F argument to [sqlite3_serialize(D,S,P,F)].
**
** SQLITE_SERIALIZE_NOCOPY means that [sqlite3_serialize()] will return
** a pointer to contiguous in-memory database that it is currently using,
** without making a copy of the database.  If SQLite is not currently using
** a contiguous in-memory database, then this option causes
** [sqlite3_serialize()] to return a NULL pointer.  SQLite will only be
** using a contiguous in-memory database if it has been initialized by a
** prior call to [sqlite3_deserialize()].
*/
SERIALIZE_NOCOPY :: 0x001 /* Do no memory allocations */


/*
** CAPI3REF: Flags for sqlite3_deserialize()
**
** The following are allowed values for the 6th argument (the F argument) to
** the [sqlite3_deserialize(D,S,P,N,M,F)] interface.
**
** The SQLITE_DESERIALIZE_FREEONCLOSE means that the database serialization
** in the P argument is held in memory obtained from [sqlite3_malloc64()]
** and that SQLite should take ownership of this memory and automatically
** free it when it has finished using it.  Without this flag, the caller
** is responsible for freeing any dynamically allocated memory.
**
** The SQLITE_DESERIALIZE_RESIZEABLE flag means that SQLite is allowed to
** grow the size of the database using calls to [sqlite3_realloc64()].  This
** flag should only be used if SQLITE_DESERIALIZE_FREEONCLOSE is also used.
** Without this flag, the deserialized database cannot increase in size beyond
** the number of bytes specified by the M parameter.
**
** The SQLITE_DESERIALIZE_READONLY flag means that the deserialized database
** should be treated as read-only.
*/
DESERIALIZE_FREEONCLOSE :: 1 /* Call sqlite3_free() on close */
DESERIALIZE_RESIZEABLE :: 2 /* Resize using sqlite3_realloc64() */
DESERIALIZE_READONLY :: 4 /* Database is read-only */


/*
** CAPI3REF: Datatypes for the CARRAY table-valued function
**
** The fifth argument to the [sqlite3_carray_bind()] interface musts be
** one of the following constants, to specify the datatype of the array
** that is being bound into the [carray table-valued function].
*/
CARRAY_INT32 :: 0 /* Data is 32-bit signed integers */
CARRAY_INT64 :: 1 /* Data is 64-bit signed integers */
CARRAY_DOUBLE :: 2 /* Data is doubles */
CARRAY_TEXT :: 3 /* Data is char* */
CARRAY_BLOB :: 4 /* Data is struct iovec */

Rtree_Dbl :: f64


/*
** A pointer to a structure of the following type is passed as the first
** argument to callbacks registered using rtree_geometry_callback().
*/
Rtree_Geometry :: struct {
	pContext: rawptr, /* Copy of pContext passed to s_r_g_c() */
	nParam:   i32, /* Size of array aParam[] */
	aParam:   ^Rtree_Dbl, /* Parameters passed to SQL geom function */
	pUser:    rawptr, /* Callback implementation user data */
	xDelUser: proc "c" (
		_: rawptr,
		/* Called by SQLite to clean up pUser */
	), /* Called by SQLite to clean up pUser */
}


/*
** A pointer to a structure of the following type is passed as the
** argument to scored geometry callback registered using
** sqlite3_rtree_query_callback().
**
** Note that the first 5 fields of this structure are identical to
** sqlite3_rtree_geometry.  This structure is a subclass of
** sqlite3_rtree_geometry.
*/
Rtree_Query_Info :: struct {
	pContext:      rawptr, /* pContext from when function registered */
	nParam:        i32, /* Number of function parameters */
	aParam:        ^Rtree_Dbl, /* value of function parameters */
	pUser:         rawptr, /* callback can use this, if desired */
	xDelUser:      proc "c" (
		_: rawptr,
		/* function to free pUser */
	), /* function to free pUser */
	aCoord:        ^Rtree_Dbl, /* Coordinates of node or entry to check */
	anQueue:       ^u32, /* Number of pending entries in the queue */
	nCoord:        i32, /* Number of coordinates */
	iLevel:        i32, /* Level of current node or entry */
	mxLevel:       i32, /* The largest iLevel value in the tree */
	iRowid:        i64, /* Rowid for current entry */
	rParentScore:  Rtree_Dbl, /* Score of parent node */
	eParentWithin: i32, /* Visibility of parent node */
	eWithin:       i32, /* OUT: Visibility */
	rScore:        Rtree_Dbl, /* OUT: Write the score here */

	/* The following fields are only available in 3.8.11 and later */
	apSqlParam:    [^]^Value, /* Original SQL values of parameters */
}

/*
** Allowed values for sqlite3_rtree_query.eWithin and .eParentWithin.
*/
NOT_WITHIN :: 0 /* Object completely outside of query region */
PARTLY_WITHIN :: 1 /* Object partially overlaps query region */
FULLY_WITHIN :: 2 /* Object fully contained within query region */

Fts5context :: struct {}
Fts5_Extension_Function :: proc "c" (
	pApi: ^Fts5extension_Api,
	pFts: ^Fts5context,
	pCtx: ^Context,
	nVal: i32,
	apVal: [^]^Value,
	/* Array of trailing arguments */
)

Fts5phrase_Iter :: struct {
	a: ^u8,
	b: ^u8,
}

/*
** EXTENSION API FUNCTIONS
**
** xUserData(pFts):
**   Return a copy of the pUserData pointer passed to the xCreateFunction()
**   API when the extension function was registered.
**
** xColumnTotalSize(pFts, iCol, pnToken):
**   If parameter iCol is less than zero, set output variable *pnToken
**   to the total number of tokens in the FTS5 table. Or, if iCol is
**   non-negative but less than the number of columns in the table, return
**   the total number of tokens in column iCol, considering all rows in
**   the FTS5 table.
**
**   If parameter iCol is greater than or equal to the number of columns
**   in the table, SQLITE_RANGE is returned. Or, if an error occurs (e.g.
**   an OOM condition or IO error), an appropriate SQLite error code is
**   returned.
**
** xColumnCount(pFts):
**   Return the number of columns in the table.
**
** xColumnSize(pFts, iCol, pnToken):
**   If parameter iCol is less than zero, set output variable *pnToken
**   to the total number of tokens in the current row. Or, if iCol is
**   non-negative but less than the number of columns in the table, set
**   *pnToken to the number of tokens in column iCol of the current row.
**
**   If parameter iCol is greater than or equal to the number of columns
**   in the table, SQLITE_RANGE is returned. Or, if an error occurs (e.g.
**   an OOM condition or IO error), an appropriate SQLite error code is
**   returned.
**
**   This function may be quite inefficient if used with an FTS5 table
**   created with the "columnsize=0" option.
**
** xColumnText:
**   If parameter iCol is less than zero, or greater than or equal to the
**   number of columns in the table, SQLITE_RANGE is returned.
**
**   Otherwise, this function attempts to retrieve the text of column iCol of
**   the current document. If successful, (*pz) is set to point to a buffer
**   containing the text in utf-8 encoding, (*pn) is set to the size in bytes
**   (not characters) of the buffer and SQLITE_OK is returned. Otherwise,
**   if an error occurs, an SQLite error code is returned and the final values
**   of (*pz) and (*pn) are undefined.
**
** xPhraseCount:
**   Returns the number of phrases in the current query expression.
**
** xPhraseSize:
**   If parameter iCol is less than zero, or greater than or equal to the
**   number of phrases in the current query, as returned by xPhraseCount,
**   0 is returned. Otherwise, this function returns the number of tokens in
**   phrase iPhrase of the query. Phrases are numbered starting from zero.
**
** xInstCount:
**   Set *pnInst to the total number of occurrences of all phrases within
**   the query within the current row. Return SQLITE_OK if successful, or
**   an error code (i.e. SQLITE_NOMEM) if an error occurs.
**
**   This API can be quite slow if used with an FTS5 table created with the
**   "detail=none" or "detail=column" option. If the FTS5 table is created
**   with either "detail=none" or "detail=column" and "content=" option
**   (i.e. if it is a contentless table), then this API always returns 0.
**
** xInst:
**   Query for the details of phrase match iIdx within the current row.
**   Phrase matches are numbered starting from zero, so the iIdx argument
**   should be greater than or equal to zero and smaller than the value
**   output by xInstCount(). If iIdx is less than zero or greater than
**   or equal to the value returned by xInstCount(), SQLITE_RANGE is returned.
**
**   Otherwise, output parameter *piPhrase is set to the phrase number, *piCol
**   to the column in which it occurs and *piOff the token offset of the
**   first token of the phrase. SQLITE_OK is returned if successful, or an
**   error code (i.e. SQLITE_NOMEM) if an error occurs.
**
**   This API can be quite slow if used with an FTS5 table created with the
**   "detail=none" or "detail=column" option.
**
** xRowid:
**   Returns the rowid of the current row.
**
** xTokenize:
**   Tokenize text using the tokenizer belonging to the FTS5 table.
**
** xQueryPhrase(pFts5, iPhrase, pUserData, xCallback):
**   This API function is used to query the FTS table for phrase iPhrase
**   of the current query. Specifically, a query equivalent to:
**
**       ... FROM ftstable WHERE ftstable MATCH $p ORDER BY rowid
**
**   with $p set to a phrase equivalent to the phrase iPhrase of the
**   current query is executed. Any column filter that applies to
**   phrase iPhrase of the current query is included in $p. For each
**   row visited, the callback function passed as the fourth argument
**   is invoked. The context and API objects passed to the callback
**   function may be used to access the properties of each matched row.
**   Invoking Api.xUserData() returns a copy of the pointer passed as
**   the third argument to pUserData.
**
**   If parameter iPhrase is less than zero, or greater than or equal to
**   the number of phrases in the query, as returned by xPhraseCount(),
**   this function returns SQLITE_RANGE.
**
**   If the callback function returns any value other than SQLITE_OK, the
**   query is abandoned and the xQueryPhrase function returns immediately.
**   If the returned value is SQLITE_DONE, xQueryPhrase returns SQLITE_OK.
**   Otherwise, the error code is propagated upwards.
**
**   If the query runs to completion without incident, SQLITE_OK is returned.
**   Or, if some error occurs before the query completes or is aborted by
**   the callback, an SQLite error code is returned.
**
**
** xSetAuxdata(pFts5, pAux, xDelete)
**
**   Save the pointer passed as the second argument as the extension function's
**   "auxiliary data". The pointer may then be retrieved by the current or any
**   future invocation of the same fts5 extension function made as part of
**   the same MATCH query using the xGetAuxdata() API.
**
**   Each extension function is allocated a single auxiliary data slot for
**   each FTS query (MATCH expression). If the extension function is invoked
**   more than once for a single FTS query, then all invocations share a
**   single auxiliary data context.
**
**   If there is already an auxiliary data pointer when this function is
**   invoked, then it is replaced by the new pointer. If an xDelete callback
**   was specified along with the original pointer, it is invoked at this
**   point.
**
**   The xDelete callback, if one is specified, is also invoked on the
**   auxiliary data pointer after the FTS5 query has finished.
**
**   If an error (e.g. an OOM condition) occurs within this function,
**   the auxiliary data is set to NULL and an error code returned. If the
**   xDelete parameter was not NULL, it is invoked on the auxiliary data
**   pointer before returning.
**
**
** xGetAuxdata(pFts5, bClear)
**
**   Returns the current auxiliary data pointer for the fts5 extension
**   function. See the xSetAuxdata() method for details.
**
**   If the bClear argument is non-zero, then the auxiliary data is cleared
**   (set to NULL) before this function returns. In this case the xDelete,
**   if any, is not invoked.
**
**
** xRowCount(pFts5, pnRow)
**
**   This function is used to retrieve the total number of rows in the table.
**   In other words, the same value that would be returned by:
**
**        SELECT count(*) FROM ftstable;
**
** xPhraseFirst()
**   This function is used, along with type Fts5PhraseIter and the xPhraseNext
**   method, to iterate through all instances of a single query phrase within
**   the current row. This is the same information as is accessible via the
**   xInstCount/xInst APIs. While the xInstCount/xInst APIs are more convenient
**   to use, this API may be faster under some circumstances. To iterate
**   through instances of phrase iPhrase, use the following code:
**
**       Fts5PhraseIter iter;
**       int iCol, iOff;
**       for(pApi->xPhraseFirst(pFts, iPhrase, &iter, &iCol, &iOff);
**           iCol>=0;
**           pApi->xPhraseNext(pFts, &iter, &iCol, &iOff)
**       ){
**         // An instance of phrase iPhrase at offset iOff of column iCol
**       }
**
**   The Fts5PhraseIter structure is defined above. Applications should not
**   modify this structure directly - it should only be used as shown above
**   with the xPhraseFirst() and xPhraseNext() API methods (and by
**   xPhraseFirstColumn() and xPhraseNextColumn() as illustrated below).
**
**   This API can be quite slow if used with an FTS5 table created with the
**   "detail=none" or "detail=column" option. If the FTS5 table is created
**   with either "detail=none" or "detail=column" and "content=" option
**   (i.e. if it is a contentless table), then this API always iterates
**   through an empty set (all calls to xPhraseFirst() set iCol to -1).
**
**   In all cases, matches are visited in (column ASC, offset ASC) order.
**   i.e. all those in column 0, sorted by offset, followed by those in
**   column 1, etc.
**
** xPhraseNext()
**   See xPhraseFirst above.
**
** xPhraseFirstColumn()
**   This function and xPhraseNextColumn() are similar to the xPhraseFirst()
**   and xPhraseNext() APIs described above. The difference is that instead
**   of iterating through all instances of a phrase in the current row, these
**   APIs are used to iterate through the set of columns in the current row
**   that contain one or more instances of a specified phrase. For example:
**
**       Fts5PhraseIter iter;
**       int iCol;
**       for(pApi->xPhraseFirstColumn(pFts, iPhrase, &iter, &iCol);
**           iCol>=0;
**           pApi->xPhraseNextColumn(pFts, &iter, &iCol)
**       ){
**         // Column iCol contains at least one instance of phrase iPhrase
**       }
**
**   This API can be quite slow if used with an FTS5 table created with the
**   "detail=none" option. If the FTS5 table is created with either
**   "detail=none" "content=" option (i.e. if it is a contentless table),
**   then this API always iterates through an empty set (all calls to
**   xPhraseFirstColumn() set iCol to -1).
**
**   The information accessed using this API and its companion
**   xPhraseFirstColumn() may also be obtained using xPhraseFirst/xPhraseNext
**   (or xInst/xInstCount). The chief advantage of this API is that it is
**   significantly more efficient than those alternatives when used with
**   "detail=column" tables.
**
** xPhraseNextColumn()
**   See xPhraseFirstColumn above.
**
** xQueryToken(pFts5, iPhrase, iToken, ppToken, pnToken)
**   This is used to access token iToken of phrase iPhrase of the current
**   query. Before returning, output parameter *ppToken is set to point
**   to a buffer containing the requested token, and *pnToken to the
**   size of this buffer in bytes.
**
**   If iPhrase or iToken are less than zero, or if iPhrase is greater than
**   or equal to the number of phrases in the query as reported by
**   xPhraseCount(), or if iToken is equal to or greater than the number of
**   tokens in the phrase, SQLITE_RANGE is returned and *ppToken and *pnToken
are both zeroed.
**
**   The output text is not a copy of the query text that specified the
**   token. It is the output of the tokenizer module. For tokendata=1
**   tables, this includes any embedded 0x00 and trailing data.
**
** xInstToken(pFts5, iIdx, iToken, ppToken, pnToken)
**   This is used to access token iToken of phrase hit iIdx within the
**   current row. If iIdx is less than zero or greater than or equal to the
**   value returned by xInstCount(), SQLITE_RANGE is returned.  Otherwise,
**   output variable (*ppToken) is set to point to a buffer containing the
**   matching document token, and (*pnToken) to the size of that buffer in
**   bytes.
**
**   The output text is not a copy of the document text that was tokenized.
**   It is the output of the tokenizer module. For tokendata=1 tables, this
**   includes any embedded 0x00 and trailing data.
**
**   This API may be slow in some cases if the token identified by parameters
**   iIdx and iToken matched a prefix token in the query. In most cases, the
**   first call to this API for each prefix token in the query is forced
**   to scan the portion of the full-text index that matches the prefix
**   token to collect the extra data required by this API. If the prefix
**   token matches a large number of token instances in the document set,
**   this may be a performance problem.
**
**   If the user knows in advance that a query may use this API for a
**   prefix token, FTS5 may be configured to collect all required data as part
**   of the initial querying of the full-text index, avoiding the second scan
**   entirely. This also causes prefix queries that do not use this API to
**   run more slowly and use more memory. FTS5 may be configured in this way
**   either on a per-table basis using the [FTS5 insttoken | 'insttoken']
**   option, or on a per-query basis using the
**   [fts5_insttoken | fts5_insttoken()] user function.
**
**   This API can be quite slow if used with an FTS5 table created with the
**   "detail=none" or "detail=column" option.
**
** xColumnLocale(pFts5, iIdx, pzLocale, pnLocale)
**   If parameter iCol is less than zero, or greater than or equal to the
**   number of columns in the table, SQLITE_RANGE is returned.
**
**   Otherwise, this function attempts to retrieve the locale associated
**   with column iCol of the current row. Usually, there is no associated
**   locale, and output parameters (*pzLocale) and (*pnLocale) are set
**   to NULL and 0, respectively. However, if the fts5_locale() function
**   was used to associate a locale with the value when it was inserted
**   into the fts5 table, then (*pzLocale) is set to point to a nul-terminated
**   buffer containing the name of the locale in utf-8 encoding. (*pnLocale)
**   is set to the size in bytes of the buffer, not including the
**   nul-terminator.
**
**   If successful, SQLITE_OK is returned. Or, if an error occurs, an
**   SQLite error code is returned. The final value of the output parameters
**   is undefined in this case.
**
** xTokenize_v2:
**   Tokenize text using the tokenizer belonging to the FTS5 table. This
**   API is the same as the xTokenize() API, except that it allows a tokenizer
**   locale to be specified.
*/
Fts5extension_Api :: struct {
	iVersion:           i32, /* Currently always set to 4 */
	xUserData:          proc "c" (_: ^Fts5context) -> rawptr,
	xColumnCount:       proc "c" (_: ^Fts5context) -> i32,
	xRowCount:          proc "c" (_: ^Fts5context, pnRow: ^i64) -> i32,
	xColumnTotalSize:   proc "c" (_: ^Fts5context, iCol: i32, pnToken: ^i64) -> i32,
	xTokenize:          proc "c" (
		_: ^Fts5context,
		pText: cstring,
		nText: i32,
		pCtx: rawptr,
		xToken: proc "c" (
			_: rawptr,
			_: i32,
			_: cstring,
			_: i32,
			_: i32,
			_: i32,
			/* Callback */
		) -> i32,
	) -> i32,
	xPhraseCount:       proc "c" (_: ^Fts5context) -> i32,
	xPhraseSize:        proc "c" (_: ^Fts5context, iPhrase: i32) -> i32,
	xInstCount:         proc "c" (_: ^Fts5context, pnInst: ^i32) -> i32,
	xInst:              proc "c" (_: ^Fts5context, iIdx: i32, piPhrase: ^i32, piCol: ^i32, piOff: ^i32) -> i32,
	xRowid:             proc "c" (_: ^Fts5context) -> i64,
	xColumnText:        proc "c" (_: ^Fts5context, iCol: i32, pz: ^cstring, pn: ^i32) -> i32,
	xColumnSize:        proc "c" (_: ^Fts5context, iCol: i32, pnToken: ^i32) -> i32,
	xQueryPhrase:       proc "c" (
		_: ^Fts5context,
		iPhrase: i32,
		pUserData: rawptr,
		_: proc "c" (_: ^Fts5extension_Api, _: ^Fts5context, _: rawptr) -> i32,
	) -> i32,
	xSetAuxdata:        proc "c" (_: ^Fts5context, pAux: rawptr, xDelete: proc "c" (_: rawptr)) -> i32,
	xGetAuxdata:        proc "c" (_: ^Fts5context, bClear: i32) -> rawptr,
	xPhraseFirst:       proc "c" (_: ^Fts5context, iPhrase: i32, _: ^Fts5phrase_Iter, _: ^i32, _: ^i32) -> i32,
	xPhraseNext:        proc "c" (_: ^Fts5context, _: ^Fts5phrase_Iter, piCol: ^i32, piOff: ^i32),
	xPhraseFirstColumn: proc "c" (_: ^Fts5context, iPhrase: i32, _: ^Fts5phrase_Iter, _: ^i32) -> i32,
	xPhraseNextColumn:  proc "c" (_: ^Fts5context, _: ^Fts5phrase_Iter, piCol: ^i32),

	/* Below this point are iVersion>=3 only */
	xQueryToken:        proc "c" (_: ^Fts5context, iPhrase: i32, iToken: i32, ppToken: ^cstring, pnToken: ^i32) -> i32,
	xInstToken:         proc "c" (_: ^Fts5context, iIdx: i32, iToken: i32, _: ^cstring, _: ^i32) -> i32,

	/* Below this point are iVersion>=4 only */
	xColumnLocale:      proc "c" (_: ^Fts5context, iCol: i32, pz: ^cstring, pn: ^i32) -> i32,
	xTokenize_v2:       proc "c" (
		_: ^Fts5context,
		pText: cstring,
		nText: i32,
		pLocale: cstring,
		nLocale: i32,
		pCtx: rawptr,
		xToken: proc "c" (
			_: rawptr,
			_: i32,
			_: cstring,
			_: i32,
			_: i32,
			_: i32,
			/* Callback */
		) -> i32,
	) -> i32,
}

Fts5tokenizer :: struct {}

Fts5_Tokenizer_V2 :: struct {
	iVersion:  i32, /* Currently always 2 */
	xCreate:   proc "c" (_: rawptr, azArg: [^]cstring, nArg: i32, ppOut: ^^Fts5tokenizer) -> i32,
	xDelete:   proc "c" (_: ^Fts5tokenizer),
	xTokenize: proc "c" (
		_: ^Fts5tokenizer,
		pCtx: rawptr,
		flags: i32,
		pText: cstring,
		nText: i32,
		pLocale: cstring,
		nLocale: i32,
		xToken: proc "c" (
			pCtx: rawptr,
			tflags: i32,
			pToken: cstring,
			nToken: i32,
			iStart: i32,
			iEnd: i32,
			/* Byte offset of end of token within input text */
		) -> i32,
	) -> i32,
}

Fts5_Tokenizer :: struct {
	xCreate:   proc "c" (_: rawptr, azArg: [^]cstring, nArg: i32, ppOut: ^^Fts5tokenizer) -> i32,
	xDelete:   proc "c" (_: ^Fts5tokenizer),
	xTokenize: proc "c" (
		_: ^Fts5tokenizer,
		pCtx: rawptr,
		flags: i32,
		pText: cstring,
		nText: i32,
		xToken: proc "c" (
			pCtx: rawptr,
			tflags: i32,
			pToken: cstring,
			nToken: i32,
			iStart: i32,
			iEnd: i32,
			/* Byte offset of end of token within input text */
		) -> i32,
	) -> i32,
}

/* Flags that may be passed as the third argument to xTokenize() */
FTS5_TOKENIZE_QUERY :: 0x0001
FTS5_TOKENIZE_PREFIX :: 0x0002
FTS5_TOKENIZE_DOCUMENT :: 0x0004
FTS5_TOKENIZE_AUX :: 0x0008

/* Flags that may be passed by the tokenizer implementation back to FTS5
** as the third argument to the supplied xToken callback. */
FTS5_TOKEN_COLOCATED :: 0x0001 /* Same position as prev. token */

Fts5_Api :: struct {
	iVersion:            i32, /* Currently always set to 3 */

	/* Create a new tokenizer */
	xCreateTokenizer:    proc "c" (pApi: ^Fts5_Api, zName: cstring, pUserData: rawptr, pTokenizer: ^Fts5_Tokenizer, xDestroy: proc "c" (_: rawptr)) -> i32,

	/* Find an existing tokenizer */
	xFindTokenizer:      proc "c" (pApi: ^Fts5_Api, zName: cstring, ppUserData: ^rawptr, pTokenizer: ^Fts5_Tokenizer) -> i32,

	/* Create a new auxiliary function */
	xCreateFunction:     proc "c" (
		pApi: ^Fts5_Api,
		zName: cstring,
		pUserData: rawptr,
		xFunction: Fts5_Extension_Function,
		xDestroy: proc "c" (_: rawptr),
	) -> i32,

	/* APIs below this point are only available if iVersion>=3 */

	/* Create a new tokenizer */
	xCreateTokenizer_v2: proc "c" (pApi: ^Fts5_Api, zName: cstring, pUserData: rawptr, pTokenizer: ^Fts5_Tokenizer_V2, xDestroy: proc "c" (_: rawptr)) -> i32,

	/* Find an existing tokenizer */
	xFindTokenizer_v2:   proc "c" (pApi: ^Fts5_Api, zName: cstring, ppUserData: ^rawptr, ppTokenizer: ^^Fts5_Tokenizer_V2) -> i32,
}


/*
** ------------------------------------------------------------------------
** Hand-written additions, appended by the bindgen footer mechanism
** (sqlite3_footer.odin). See bindgen.sjson.
**
** The enums below mirror the plain constants generated from the C macros;
** the values are identical. They exist so that procedures which return or
** accept these codes can be strongly typed via procedure_type_overrides.
** ------------------------------------------------------------------------
*/

/* All primary and extended result codes, see the [result codes] and
** [extended result codes] documentation above. */
Result_Code :: enum i32 {
	OK                      = 0, /* Successful result */
	ERROR                   = 1, /* Generic error */
	INTERNAL                = 2, /* Internal logic error in SQLite */
	PERM                    = 3, /* Access permission denied */
	ABORT                   = 4, /* Callback routine requested an abort */
	BUSY                    = 5, /* The database file is locked */
	LOCKED                  = 6, /* A table in the database is locked */
	NOMEM                   = 7, /* A malloc() failed */
	READONLY                = 8, /* Attempt to write a readonly database */
	INTERRUPT               = 9, /* Operation terminated by sqlite3_interrupt() */
	IOERR                   = 10, /* Some kind of disk I/O error occurred */
	CORRUPT                 = 11, /* The database disk image is malformed */
	NOTFOUND                = 12, /* Unknown opcode in sqlite3_file_control() */
	FULL                    = 13, /* Insertion failed because database is full */
	CANTOPEN                = 14, /* Unable to open the database file */
	PROTOCOL                = 15, /* Database lock protocol error */
	EMPTY                   = 16, /* Internal use only */
	SCHEMA                  = 17, /* The database schema changed */
	TOOBIG                  = 18, /* String or BLOB exceeds size limit */
	CONSTRAINT              = 19, /* Abort due to constraint violation */
	MISMATCH                = 20, /* Data type mismatch */
	MISUSE                  = 21, /* Library used incorrectly */
	NOLFS                   = 22, /* Uses OS features not supported on host */
	AUTH                    = 23, /* Authorization denied */
	FORMAT                  = 24, /* Not used */
	RANGE                   = 25, /* 2nd parameter to sqlite3_bind out of range */
	NOTADB                  = 26, /* File opened that is not a database file */
	NOTICE                  = 27, /* Notifications from sqlite3_log() */
	WARNING                 = 28, /* Warnings from sqlite3_log() */
	ROW                     = 100, /* sqlite3_step() has another row ready */
	DONE                    = 101, /* sqlite3_step() has finished executing */
	/* extended result codes */
	ERROR_MISSING_COLLSEQ   = 257,
	ERROR_RETRY             = 513,
	ERROR_SNAPSHOT          = 769,
	ERROR_RESERVESIZE       = 1025,
	ERROR_KEY               = 1281,
	ERROR_UNABLE            = 1537,
	IOERR_READ              = 266,
	IOERR_SHORT_READ        = 522,
	IOERR_WRITE             = 778,
	IOERR_FSYNC             = 1034,
	IOERR_DIR_FSYNC         = 1290,
	IOERR_TRUNCATE          = 1546,
	IOERR_FSTAT             = 1802,
	IOERR_UNLOCK            = 2058,
	IOERR_RDLOCK            = 2314,
	IOERR_DELETE            = 2570,
	IOERR_BLOCKED           = 2826,
	IOERR_NOMEM             = 3082,
	IOERR_ACCESS            = 3338,
	IOERR_CHECKRESERVEDLOCK = 3594,
	IOERR_LOCK              = 3850,
	IOERR_CLOSE             = 4106,
	IOERR_DIR_CLOSE         = 4362,
	IOERR_SHMOPEN           = 4618,
	IOERR_SHMSIZE           = 4874,
	IOERR_SHMLOCK           = 5130,
	IOERR_SHMMAP            = 5386,
	IOERR_SEEK              = 5642,
	IOERR_DELETE_NOENT      = 5898,
	IOERR_MMAP              = 6154,
	IOERR_GETTEMPPATH       = 6410,
	IOERR_CONVPATH          = 6666,
	IOERR_VNODE             = 6922,
	IOERR_AUTH              = 7178,
	IOERR_BEGIN_ATOMIC      = 7434,
	IOERR_COMMIT_ATOMIC     = 7690,
	IOERR_ROLLBACK_ATOMIC   = 7946,
	IOERR_DATA              = 8202,
	IOERR_CORRUPTFS         = 8458,
	IOERR_IN_PAGE           = 8714,
	IOERR_BADKEY            = 8970,
	IOERR_CODEC             = 9226,
	LOCKED_SHAREDCACHE      = 262,
	LOCKED_VTAB             = 518,
	BUSY_RECOVERY           = 261,
	BUSY_SNAPSHOT           = 517,
	BUSY_TIMEOUT            = 773,
	CANTOPEN_NOTEMPDIR      = 270,
	CANTOPEN_ISDIR          = 526,
	CANTOPEN_FULLPATH       = 782,
	CANTOPEN_CONVPATH       = 1038,
	CANTOPEN_DIRTYWAL       = 1294, /* Not Used */
	CANTOPEN_SYMLINK        = 1550,
	CORRUPT_VTAB            = 267,
	CORRUPT_SEQUENCE        = 523,
	CORRUPT_INDEX           = 779,
	READONLY_RECOVERY       = 264,
	READONLY_CANTLOCK       = 520,
	READONLY_ROLLBACK       = 776,
	READONLY_DBMOVED        = 1032,
	READONLY_CANTINIT       = 1288,
	READONLY_DIRECTORY      = 1544,
	ABORT_ROLLBACK          = 516,
	CONSTRAINT_CHECK        = 275,
	CONSTRAINT_COMMITHOOK   = 531,
	CONSTRAINT_FOREIGNKEY   = 787,
	CONSTRAINT_FUNCTION     = 1043,
	CONSTRAINT_NOTNULL      = 1299,
	CONSTRAINT_PRIMARYKEY   = 1555,
	CONSTRAINT_TRIGGER      = 1811,
	CONSTRAINT_UNIQUE       = 2067,
	CONSTRAINT_VTAB         = 2323,
	CONSTRAINT_ROWID        = 2579,
	CONSTRAINT_PINNED       = 2835,
	CONSTRAINT_DATATYPE     = 3091,
	NOTICE_RECOVER_WAL      = 283,
	NOTICE_RECOVER_ROLLBACK = 539,
	NOTICE_RBU              = 795,
	WARNING_AUTOINDEX       = 284,
	AUTH_USER               = 279,
	OK_LOAD_PERMANENTLY     = 256,
	OK_SYMLINK              = 512, /* internal only */
}

/* Fundamental datatypes returned by column_type()/value_type(). */
Datatype :: enum i32 {
	INTEGER = 1,
	FLOAT   = 2,
	TEXT    = 3,
	BLOB    = 4,
	NULL    = 5,
}

/* Conflict resolution modes returned by vtab_on_conflict(). IGNORE and
** ABORT share their values with the authorizer's IGNORE constant and
** Result_Code.ABORT respectively, as in the C API. */
Conflict_Resolution :: enum i32 {
	ROLLBACK = 1,
	IGNORE   = 2,
	FAIL     = 3,
	ABORT    = 4,
	REPLACE  = 5,
}

/* Special destructor values for bind_blob()/bind_text()/result_text() etc.
** In C these are the constants ((sqlite3_destructor_type)0) and
** ((sqlite3_destructor_type)-1); they are removed by the config and
** recreated here because a C cast cannot be expressed as an Odin constant. */
STATIC := Destructor_Type(nil)
TRANSIENT := transmute(Destructor_Type)(~uintptr(0))
