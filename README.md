# Rifle

> [!CAUTION]
> **Rifle is under active development.** Features may be incomplete or unstable, and breaking changes may occur without notice. It is not yet recommended for production use.

Rifle is a globally ordered, append-only, fixed-width storage engine built as a primitive for logs, queues, and IPC. It integrates with SQLite via a virtual table, letting you run SQL queries directly over in-memory and on-disk records without copying them into an external database.

Rifle is lightweight by design: an instance owns no threads and makes no allocations after startup. Single-threaded append performance[^hardware]:

| Record size | Million records/s | Throughput | Data written | Duration |
|------------:|------------------:|-----------:|-------------:|---------:|
| 8 bytes     | 97.79             | 0.73 GiB/s | 16 GiB       | 21.96 s  |
| 16 bytes    | 96.03             | 1.43 GiB/s | 32 GiB       | 22.36 s  |
| 32 bytes    | 90.77             | 2.71 GiB/s | 64 GiB       | 23.66 s  |
| 64 bytes    | 68.59             | 4.09 GiB/s | 128 GiB      | 31.31 s  |

[^hardware]: AMD Ryzen 9 9950X · Three-drive NVMe RAID 0 · Single thread · Individual records · ~8 MiB RSS · Sync request every 512 KiB

On this machine, `fio` measured a maximum sequential write throughput of 4.15 GiB/s—meaning Rifle is already I/O-bound at 64-byte records and should scale higher on faster storage.



```c
#include "rifle.h"

void write_records(RifleLog *log, int64_t total) {
    uint8_t record[32] = {0};
    int64_t sync_interval = log->config.ring_size_bytes / 2;
    int64_t bytes_written = 0;

    for (int64_t i = 0; i < total; i++) {
        // populate record ...

        int64_t index = 0;
        if (rifle_log_write(log, record, sizeof(record), 1, &index) != RIFLE_NONE) {
            // handle write error
        }

        bytes_written += sizeof(record);
        if (bytes_written >= sync_interval) {
            int64_t synced_to = 0;
            bool    progressed = false;
            rifle_log_sync(log, &synced_to);
            rifle_log_poll(log, &progressed);
            bytes_written = 0;
        }
    }

    // Flush any remaining records
    int64_t synced_to = 0;
    bool    progressed = false;
    rifle_log_sync(log, &synced_to);
    rifle_log_poll(log, &progressed);
}
```