# Rifle

> [!CAUTION]
> **Rifle is under active development.** Features may be incomplete or unstable, and breaking changes may occur without notice. It is not yet recommended for production use.

Rifle is a globally ordered, append-only, fixed-width storage engine built as a primitive for logs, queues, and IPC. It integrates with SQLite via a virtual table, letting you run SQL queries directly over in-memory and on-disk records without copying them into an external database. 
Rifle is lightweight by design; it owns no threads and makes no allocations after startup.

### Performance

Single-threaded append performance[^hardware]:

| Record size | Million records/s | Throughput | Data written | Duration |
|------------:|------------------:|-----------:|-------------:|---------:|
| 8 bytes     | 97.79             | 0.73 GiB/s | 16 GiB       | 21.96 s  |
| 16 bytes    | 96.03             | 1.43 GiB/s | 32 GiB       | 22.36 s  |
| 32 bytes    | 90.77             | 2.71 GiB/s | 64 GiB       | 23.66 s  |
| 64 bytes    | 68.59             | 4.09 GiB/s | 128 GiB      | 31.31 s  |

Log append visibility latency (between threads):

| Record size | Append rate | p50 | p99 | p99.9 |
|---:|---:|---:|---:|---:|
| 256 bytes | 100k/s | 120 ns | 130 ns | 160 ns |

On this machine, using `fio`, we measured a maximum sequential write throughput of 4.15 GiB/s—meaning Rifle is already I/O-bound at 64-byte records in this benchmark and should scale higher on faster storage.

[^hardware]: AMD Ryzen 9 9950X · Three-drive NVMe RAID 0 · Single thread · Individual records · ~8 MiB RSS · Sync request every 512 KiB

### Getting Started

Rifle is also very simple to use - these five functions are all that is needed to get started using Rifle:

```c
RifleError rifle_log_init(const RifleLogConfig config, const char *log_file, RifleLog **out_log);
RifleError rifle_log_write(RifleLog *log, const void *data, size_t data_size, int64_t count, int64_t *out_index);
RifleError rifle_log_poll(RifleLog *log, bool *out_progress);
RifleError rifle_log_read(RifleLog *log, void *buffer, size_t buffer_size, int64_t index, int64_t count);
RifleError rifle_log_deinit(RifleLog *log);
```

*This section is incomplete and I'll be adding some more guidance on using Rifle imminently*

The full API documentation can be found [here](https://www.gemmins.com/rifle/docs/rifle_8h.html).

### Querying Your Data

To be able to query your Rifle log, you can use the included SQLite virtual table implementation.
This is provided as a [Run-Time Loadable Extension](https://www.sqlite.org/loadext.html) and can be used simply in the sqlite command-line shell by running `.load <path-to-vtab.so>`, after compiling the extension using `make vtab`.

Ensure you have an existing log with a schema definition provided at intialisation.

Then, once the extension is loaded in the shell, use the command `CREATE VIRTUAL TABLE <tablename> USING rifle(<path-to-your-log>/base.rfl)` .

You should then be able to see your new table, with a schema mirroring the one you defined when initalising the log. You can now query this as if it were any other SQLite table, including joining it with other Rifle virtual tables.

*This section is incomplete and I'll be adding some more guidance on using Rifle's SQLite extension imminently*


### Basic Usage Example Example

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
            bool progressed = false;
            rifle_log_sync(log, &synced_to); // Request writes be fsynced
            rifle_log_poll(log, &progressed); // Handle I/O submission & completion
            bytes_written = 0;
        }
    }

    // Flush any remaining records
    int64_t synced_to = 0;
    bool progressed = false;
    rifle_log_sync(log, &synced_to);
    rifle_log_poll(log, &progressed);
    // May need to poll in a loop here until log indexes indicate all submitted writes have completed
}
```