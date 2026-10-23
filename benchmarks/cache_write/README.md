# Sequential cache writes

Build with `make bench-cache-write`, then select a directory on the disk to measure:

```sh
./bin/cache-write --dir /mnt/nvme --batch 1
./bin/cache-write --dir /mnt/nvme --batch 16
./bin/cache-write --dir /mnt/nvme --batch 128
```

Defaults: 256 MiB written through a 64 MiB cache, 64-byte records, 8 KiB pages,
1 GiB files. `--bytes`, `--cache-bytes`, and `--file-bytes` accept byte counts.
Data must exceed cache capacity and fill whole pages. Batches are limited to
128 records. At most 16 files can be used with the current sync queue.

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

This is a single-thread cache + uring baseline. Run repeatedly on an otherwise
idle machine; use larger datasets for sustained storage measurements. Results on
`/tmp` or a container filesystem are only useful as a smoke check.
