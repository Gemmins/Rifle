#ifndef RIFLE_H
#define RIFLE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#ifndef __cplusplus
#include <stdalign.h>
#endif

#ifdef __cplusplus
extern "C" {
#endif


/** @brief All functions return `RIFLE_NONE` on success.
 * @note These will be changing in the near future.
 */
typedef intptr_t RifleError;
enum RifleErrorValues {
    RIFLE_NONE = 0,
    RIFLE_ALLOCATOR_ERROR = 1,
    RIFLE_BUFFER_TOO_SMALL_ERROR = 2,
    RIFLE_INDEX_OUT_OF_BOUNDS_ERROR = 3,
    RIFLE_INVALID_ARG_ERROR = 4,
    RIFLE_FILE_OPERATION_ERROR = 5,
    RIFLE_GENERIC_ERROR = 6,
    RIFLE_FILE_NOT_READY = 7,
    RIFLE_UNSUPPORTED_PLATFORM_ERROR = 8,
    RIFLE_UNIMPLEMENTED_ERROR = 9,
    RIFLE_INVALID_FILE_FORMAT_ERROR = 10
};

typedef uint8_t RifleFieldType;
enum RifleFieldTypeValues {
    RIFLE_FIELD_INVALID = 0,
    RIFLE_FIELD_I8 = 1,
    RIFLE_FIELD_I16 = 2,
    RIFLE_FIELD_I32 = 3,
    RIFLE_FIELD_I64 = 4,
    RIFLE_FIELD_U8 = 10,
    RIFLE_FIELD_U16 = 11,
    RIFLE_FIELD_U32 = 12,
    RIFLE_FIELD_U64 = 13,
    RIFLE_FIELD_F32 = 20,
    RIFLE_FIELD_F64 = 21,
    RIFLE_FIELD_BOOL = 30,
    RIFLE_FIELD_BYTES = 40,
    RIFLE_FIELD_TEXT = 41
};

/** @brief String type for schema field names.
 * @note No NUL terminator is required. */
typedef struct RifleString {
    const char *data;
    intptr_t length; /**< Length of string in bytes. */
} RifleString;

/** @brief One field within a record */
typedef struct RifleSchemaField {
    RifleString name; /**< Name of the field */
    RifleFieldType type; /**< Datatype of the field */
    int64_t offset; /**< Absolute byte offset within a record. */
    int64_t size;   /**< Desired length in bytes for TEXT or BYTES fields; set to zero otherwise */
} RifleSchemaField;

/** @brief In-order list of fields which make up a record */
typedef struct RifleSchemaFields {
    const RifleSchemaField *data;
    intptr_t length; /**< Number of fields */
} RifleSchemaFields;

/** @brief Definition of the record schema of the log */
typedef struct RifleRecordSchema {
    int64_t record_size;  /** Size in bytes of the record. The size must match that derived from the list of fields. */
    RifleSchemaFields fields;
} RifleRecordSchema;

/** @brief Exposes the configurable values for a log instance */
typedef struct RifleLogConfig {
    const char *log_path;       /**< The location in which all log files will reside, NUL-terminated; must currently already exist */
    int64_t ring_size_bytes;   /**< The size of the cache used for writing records. Must be a power of 2 and < 64G */
    int64_t page_cache_size_bytes;  /**< The size of the cache used for reading records. Must be a power of 2 and > 4*page_size_bytes */
    int64_t file_size_bytes;   /**< The size of files that records are written into. Must be a positive multiple of page_size_bytes. */
    int64_t page_size_bytes;   /**< The size of memory blocks used within the page cache. Power of two, >= 4096 and <= INT32_MAX. */
    uint16_t max_open_files;   /**< The maximum number file handles the log can have open at any one time. [1,4096] */
    int64_t read_chunk_size;   /**< Large disk reads will be done in chunks. Pages per read chunk; 0 uses the number of sets. */
    int64_t commit_ring_size;  /**< Max number of complete written records ahead of visibility. Must be a positive power of two. */
    RifleRecordSchema schema;
} RifleLogConfig;

/** @brief Padded int64 to have values on their own cache line. 
 * @note May eventually change to account for differing cache line widths.
*/
typedef struct RifleIndex {
    alignas(128) int64_t value;
    uint8_t _padding[120];
} RifleIndex;

/** @brief Structure representing public fields of an individual log.
 * @note This is allocated by init into shared memory -
 *  you should not try to copy, allocate or free this yourself.
 * @note For safe concurrent use of the indexes, "atomic" reads should be used.
 *  For GCC/Clang: `__atomic_load_n(&log->visible_index.value, __ATOMIC_ACQUIRE)`
 */
typedef struct RifleLog {
    RifleIndex commited_index;    /**< End of reserved records; writes may be unfinished. */
    RifleIndex visible_index;     /**< End of the contiguous readable record range. */
    RifleIndex persisted_index;   /**< Completed data-write frontier; not necessarily durable. */
    RifleIndex durable_index;     /**< Durability frontier. */
    RifleIndex trailing_index;    /**< First record not dropped. */
    RifleLogConfig config;        /**< Effective configuration; read-only after initialization. */
} RifleLog;

/** @brief Set the default config values: 64 MiB cache, 4 GiB files, 4 KiB pages,
 * 256 open files and 256 commit slots.
 * @note Path and schema must be supplied by the user.
 * @param[out] out_config Location to output the config.
 */
RifleError rifle_log_default_config(RifleLogConfig *out_config);

/** @brief Initialise log - passing log_file will open a pre-existing one.
 * @param[in] config Configuration for this instance of the log. All strings in this object can be freed after it returns.
 * @param[in] log_file Pass NULL for log_file to create a log, or a NUL-terminated path
 * to reopen one.
 * @note On reopen, the schema is loaded from disk; `config.schema` is ignored.
 * @param[out] out_log Location to store pointer to the log in shared memory
 */
RifleError rifle_log_init(const RifleLogConfig config, const char *log_file, RifleLog **out_log);

/** @brief Release all resources associated with the log, including the log itself.
 * @note Currently need to sync before calling this to avoid loss of records
 * @param[in,out] log Log instance to operate on.
 */
RifleError rifle_log_deinit(RifleLog *log);

/** @brief Read `count` records starting at `index`.
 * @param[in,out] log Log instance to operate on.
 * @param[out] buffer Buffer to copy data in to.
 * @param[in] buffer_size buffer_size is in bytes and must cover `count * record_size`.
 * @param[in] index Index of first record in range.
 * @param[in] count Number of records to be read.
 */
RifleError rifle_log_read(RifleLog *log, void *buffer, size_t buffer_size, int64_t index, int64_t count);

/** @brief Acquire a reference to a range of records within the cache.
 * @pre Range must not cross cache page boundary
 * @note *UNIMPLEMENTED*
 * @param[in,out] log Log instance to operate on.
 * @param[in] index Index of first record in range to acquire.
 * @param[in] count Number of records to be read.
 * @param[out] out_buf Location to store pointer to buffer in cache.
 */
RifleError rifle_log_read_acquire(RifleLog *log, int64_t index, int64_t count, const void **out_buf);

/** @brief Release a reference to a range of records within the cache
 * @note *UNIMPLEMENTED*
 * @param[in,out] log Log instance to operate on.
 * @param[in] index Index of first record in the acquired range.
 */
RifleError rifle_log_read_release(RifleLog *log, int64_t index);

/** @brief Request the log to try load the range of records into its cache
 * @note *UNIMPLEMENTED*
 * @param[in,out] log Log instance to operate on.
 * @param[in] index Index of first record in range to prefetch.
 * @param[in] count Number of records to be prefetched.
 */
RifleError rifle_log_prefetch(RifleLog *log, int64_t index, int64_t count);

/** @brief Append `count` records and return their starting index.
 * @param[in,out] log Log instance to operate on.
 * @param[in] data Data to be copied into the log.
 * @note Successful completion of this function does not imply visibility.
 * @param[in] data_size Size of data, in bytes. Should be count * record_size.
 * @param[in] count Number of records to write
 * @param[out] out_index Pointer to store index of first record written in the range.
 */
RifleError rifle_log_write(RifleLog *log, const void *data, size_t data_size, int64_t count, int64_t *out_index);

/** @brief Reserve a reference to a location within the cache to write a range of records.
 * @pre Range must not exceed size of write cache.
 * @note *UNIMPLEMENTED*
 * @param[in,out] log Log instance to operate on.
 * @param[in] count
 * @param[out] out_index
 * @param[out] out_buf
 */
RifleError rifle_log_write_reserve(RifleLog *log, int64_t count, int64_t *out_index, void **out_buf);

/** @brief Signal completion of writing to a reserved range within the cache.
 * @note *UNIMPLEMENTED*
 * @param[in,out] log Log instance to operate on.
 * @param[in] index
 */
RifleError rifle_log_write_commit(RifleLog *log, int64_t index);

/** @brief Discard records with indices below index. Records below the index will become immediately inaccesible.
 * Records will only be removed from disk once a whole file is below the tail index.
 * @param[in,out] log Log instance to operate on.
 * @param[in] index Index must be < visible head.
 */
RifleError rifle_log_drop(RifleLog *log, int64_t index);

/** @brief Progress pending IO;
 * @param[in,out] log Log instance to operate on.
 * @param[out] out_progress out_progress reports whether the routine was executed.
 * False indicates that another thread was within the poll routine at that time.
 * It may also be true when an IO error is returned.
 */
RifleError rifle_log_poll(RifleLog *log, bool *out_progress);

/** @brief Request persistence of all visible records,
 * @param[in,out] log Log instance to operate on.
 * @note This is asynchronous; continue polling to progress IO.
 * @param[out] out_index returning the prefix for which records will be persisted.
 */
RifleError rifle_log_sync(RifleLog *log, int64_t *out_index);

#ifdef __cplusplus
}
#endif

#endif
