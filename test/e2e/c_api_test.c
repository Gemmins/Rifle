#define _GNU_SOURCE

#include "rifle.h"

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#if INTPTR_MAX == INT64_MAX
_Static_assert(sizeof(RifleLogConfig) == 88, "RifleLogConfig size");
_Static_assert(offsetof(RifleLogConfig, schema) == 64, "RifleLogConfig.schema offset");
_Static_assert(sizeof(RifleRecordSchema) == 24, "RifleRecordSchema size");
_Static_assert(sizeof(RifleSchemaField) == 40, "RifleSchemaField size");
_Static_assert(offsetof(RifleSchemaField, type) == 16, "RifleSchemaField.type offset");
_Static_assert(offsetof(RifleSchemaField, offset) == 24, "RifleSchemaField.offset offset");
_Static_assert(offsetof(RifleSchemaField, size) == 32, "RifleSchemaField.size offset");
_Static_assert(sizeof(RifleIndex) == 128, "RifleIndex size");
_Static_assert(_Alignof(RifleIndex) == 128, "RifleIndex alignment");
_Static_assert(offsetof(RifleLog, config) == 640, "RifleLog.config offset");
#endif

int main(void) {
    char directory[] = "/tmp/rifle-c-e2e-XXXXXX";
    assert(mkdtemp(directory) != NULL);

    const char field_name[] = "value";
    RifleSchemaField field = {
        .name = {field_name, 5},
        .type = RIFLE_FIELD_I64,
        .offset = 0,
        .size = 0,
    };
    RifleLogConfig config;
    assert(rifle_log_default_config(&config) == RIFLE_NONE);
    config.log_path = directory;
    config.ring_size_bytes = INT64_C(1) << 16;
    config.page_cache_size_bytes = 4 * 4096;
    config.file_size_bytes = 2 * 4096;
    config.page_size_bytes = 4096;
    config.max_open_files = 8;
    config.commit_ring_size = 64;
    config.schema.record_size = 8;
    config.schema.fields.data = &field;
    config.schema.fields.length = 1;

    RifleLog *log = NULL;
    assert(rifle_log_init(config, NULL, &log) == RIFLE_NONE);
    assert(log != NULL);

    int64_t input[2048];
    int64_t output[2048];
    for (int64_t i = 0; i < 2048; ++i) input[i] = i + 1;

    int64_t index = -1;
    assert(rifle_log_write(log, input, sizeof(input), 2048, &index) == RIFLE_NONE);
    assert(index == 0);

    int64_t target = 0;
    assert(rifle_log_sync(log, &target) == RIFLE_NONE);
    assert(target == 2048);
    for (int attempt = 0; attempt < 100000; ++attempt) {
        if (__atomic_load_n(&log->durable_index.value, __ATOMIC_ACQUIRE) >= target) break;
        bool progress = false;
        assert(rifle_log_poll(log, &progress) == RIFLE_NONE);
        assert(progress);
    }
    assert(__atomic_load_n(&log->durable_index.value, __ATOMIC_ACQUIRE) == target);

    memset(output, 0, sizeof(output));
    assert(rifle_log_read(log, output, sizeof(output), 0, 2048) == RIFLE_NONE);
    assert(memcmp(input, output, sizeof(input)) == 0);
    assert(rifle_log_deinit(log) == RIFLE_NONE);

    char base_path[512];
    assert(snprintf(base_path, sizeof(base_path), "%s/base.rfl", directory) > 0);
    config.schema = (RifleRecordSchema){0};
    RifleLog *reopened = NULL;
    assert(rifle_log_init(config, base_path, &reopened) == RIFLE_NONE);
    memset(output, 0, sizeof(output));
    assert(rifle_log_read(reopened, output, sizeof(output), 0, 2048) == RIFLE_NONE);
    assert(memcmp(input, output, sizeof(input)) == 0);
    assert(rifle_log_deinit(reopened) == RIFLE_NONE);

    char data_path[512];
    for (int file_id = 0; file_id < 2; ++file_id) {
        assert(snprintf(data_path, sizeof(data_path), "%s/data_%020d.rfl", directory, file_id) > 0);
        assert(unlink(data_path) == 0);
    }
    assert(unlink(base_path) == 0);
    assert(rmdir(directory) == 0);
    return 0;
}
