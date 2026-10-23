# Sequential cache writes

Build with `make bench-cache-write`, then select a directory on the disk to measure:

```sh
./bin/cache-write --dir /mnt/nvme --batch 1
./bin/cache-write --dir /mnt/nvme --batch 16
./bin/cache-write --dir /mnt/nvme --batch 128
```

Defaults: 256 MiB written through a 64 MiB cache, 64-byte records, 8 KiB pages,
1 GiB files. `--bytes`, `--cache-bytes`, `--file-bytes`, and `--page-size` accept
byte counts. Page size must be a multiple of 4096 bytes, cache size a multiple
of four pages, and data/file sizes whole page multiples. Data must exceed cache
capacity. Batches must fit within one page (128 records with the default page
size). At most 16 files can be used with the current sync queue.

For 32 KiB pages, without changing the number of records per cache call:

```sh
./bin/cache-write --dir . --batch 1 --page-size 32768 --bytes 17179869184 --io-thread
```

Each run creates its own directory beneath `--dir` and removes it after success.
Files are preallocated to their configured size, so allow enough free space.
On an I/O failure the process exits immediately and leaves the printed directory
for inspection; remove it manually afterward.

Initialization and source-buffer preparation are outside the timer. The write
timer includes copying, eviction, polling, file creation/allocation, and draining
all write completions. A small I/O polling wrapper counts completed bytes and
stops on errors, short writes, or 60 seconds without progress. The source buffer
is reused between batches. Final sync latency is measured separately; the write
throughput alone does not measure durable throughput.

Add `--io-thread` to run a second thread continuously calling cache poll:

```sh
./bin/cache-write --dir . --batch 1 --bytes 17179869184 --io-thread
```

The writer yields while waiting for final writes and sync in this mode. Cache
writes can still poll internally under cache pressure, so this is an additional
poller, not exclusive I/O ownership. Thread creation and joining are outside the
timer. Without the flag, the benchmark remains single-threaded.

Run repeatedly on an otherwise
idle machine; use larger datasets for sustained storage measurements. Results on
`/tmp` or a container filesystem are only useful as a smoke check.
