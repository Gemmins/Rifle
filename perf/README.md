# Rifle log benchmarks

Linux, Odin, and Python 3.9+; no Python packages or plotting tools required.
Run commands from the repository root (the Python scripts also work from any
directory).

```sh
python3 perf/run.py --quick                       # smoke test, not a performance baseline
python3 perf/run.py --list                        # inspect the default matrix
python3 perf/run.py --data-dir /path/on/test/disk  # standard suite
```

The runner builds with `-o:speed -vet`, runs each trial in a fresh process with
a fresh log, prints a summary, and saves incremental JSONL in `perf/results/`.
Choose `--data-dir` on the filesystem you intend to measure. The default is
`perf/.data/`; `/tmp` may be a memory filesystem. Trial logs are removed after
each run, including failures and timeouts. Existing result files are never
overwritten.

## Workloads

| Name | Pattern | What it measures |
| --- | --- | --- |
| `append` | Every worker appends one record per call | Small event ingestion and writer contention |
| `batch` | Every worker appends batches (default 64 records) | Amortization from producer buffering |
| `scan` | Readers replay separate contiguous portions of the fixture, wrapping within their own portions | Parallel replay and batch reads |
| `random` | Uniform, single-record reads over the entire fixture | Lookup workload larger than rifle's cache |
| `hot` | Uniform reads over an explicitly prewarmed quarter-cache region | Resident lookup overhead and reader contention |
| `mixed` | Each worker randomly chooses 50% historical reads, 50% new appends by default | Balanced operation mix; set `--read-percent` for read-heavy or write-heavy traffic |
| `checkpoint` | Concurrent batched appends, followed by a shared checkpoint every 4 MiB | Group commit, including the wait for durability |

Defaults sweep **64, 256, 1000, 4096-byte records** and **1, 2, 4, 8 client
threads**. The 1000-byte case deliberately crosses page boundaries and leaves
partial pages. All sizes include a 16-byte sequence/writer header. Records have
deterministic nonzero payloads; sequence stamps are updated for each write.

To keep the default suite manageable, record sizes vary at one thread, and
thread counts vary at 256 bytes: 49 cases, three repetitions each. `--matrix
full` takes the full workload × size × thread product. The first value in
`--sizes` and `--threads` sets the sweep baseline. Trial order is shuffled with
a recorded seed; access sequences are deterministic for each configuration.

```sh
# A focused comparison, with longer trials and a named result file:
python3 perf/run.py --workloads append,batch,mixed --sizes 256,1000 \
  --threads 1,2,4 --work-mib 256 --repeats 5 --out perf/results/before.jsonl

# All size/thread combinations; change batch size or memory budgets explicitly:
python3 perf/run.py --workloads scan,random --matrix full \
  --sizes 64,256,4096 --threads 1,4 --cache-mib 16 --dataset-mib 64

# Remove operation-latency sampling to assess its throughput overhead:
python3 perf/run.py --workloads batch --sample-every 0

# Explicit mixed ratios (percentages are by operation count):
python3 perf/run.py --workloads mixed --read-percent 50  # balanced
python3 perf/run.py --workloads mixed --read-percent 10  # 90% writes
python3 perf/run.py --workloads mixed --read-percent 90  # 90% reads
```

`--quick` overrides size/thread/repeat and byte-budget options: three size/thread
points per selected workload, one repeat, a 1 MiB cache and 4 MiB fixture/work.
It is for exercising the suite. Use `--help` for all options.

## Reading the results

```sh
python3 perf/report.py perf/results/before.jsonl
python3 perf/report.py perf/results/after.jsonl --baseline perf/results/before.jsonl
python3 perf/report.py perf/results/after.jsonl --csv /tmp/rifle-summary.csv
```

The text table shows:

- **ok/all**: successful trials / attempted trials. Failures never become zero
  throughput observations or enter medians. A successful subset is incomplete.
- **Mrec/s**, **MiB/s**, **Kcall/s**: median records, logical payload bytes, and
  API calls per second. A 64-record batch is one call, not 64 calls.
- **spread%**: `(maximum - minimum) / median` across repeat throughput values.
  High spread suggests more repetitions or investigating machine load.
- **read99/write99**: median of each trial's sampled p99 call latency in
  microseconds. These are whole-call latencies, including batch calls.
- **sync99**: checkpoint p99, including `log_sync` and polling until its target
  is durable. Checkpoint rows report checkpoint latency instead of per-write
  latency; short runs have too few checkpoints for stable tail estimates.
- **vs base**: throughput change against an identical configuration; positive
  means faster. Mismatched settings show `n/a`. Environment changes are flagged.

CSV also includes p50/p95, sample counts, elapsed time, separate read/write
rates, and all workload settings. JSONL retains every trial and error plus
compiler, build flags, source hash, git state, CPU, affinity, kernel and
filesystem information. No graphs are necessary to use the suite.

Mixed rows show their ratio explicitly: `mixed-50r` means 50% reads and 50%
appends. Older result files remain labelled `mixed-90r` and are not compared
with the new balanced default. Reads still choose uniformly across the seeded
fixture: equal operation counts do not imply equal time spent reading and
writing, and cache-missing reads may dominate even a balanced mix.

## Measurement contract

- **Use the intended complete log interface.** All IO goes through `log_init`,
  `log_write`, `log_read`, `log_poll`, `log_sync`, and `log_deinit`. No direct
  cache or io_uring calls. The one field observation is an atomic load of the
  log's exposed `durable_index`, because there is no completion accessor.
- **One coordinator plus N workers.** The coordinator actively polls IO;
  `--threads` counts client workers only. Allocate CPU capacity for N + 1
  threads when assessing scaling. No affinity is imposed by the harness.
- **Fixed aggregate work.** `--work-mib` is the sum of records transferred by
  all workers, rounded down to a whole record. Increasing threads partitions
  the same work. Mixed counts reads plus writes; its ratio is probabilistic.
- **Setup is untimed.** Each trial seeds and checkpoints the fixture (32 MiB
  by default, at least twice the cache), allocates worker buffers and samples,
  and waits for every worker before releasing a shared start gate. Hot reads
  additionally prewarm their small working set. Other read cases are neither
  cold-start nor guaranteed physical-disk tests; OS/device caches are not reset.
- **API completion versus durability.** Ordinary throughput ends at the last
  worker's completion and may leave IO outstanding. Checkpoint throughput
  includes appends and the following durable wait. Checkpoint rounds exclude
  worker creation, sample aggregation and verification between rounds, so they
  measure active group-commit service time, not continuous process throughput.
- **Monotonic clocks and bounded sampling.** Every 64th API call is timed by
  default, with per-worker offsets. Sampling, record stamping, access selection
  and cheap read checks contribute to throughput; full payload verification,
  setup, sorting and teardown do not. There is no per-record allocation or
  output in the timed loop. These are closed-loop saturation tests, not
  externally paced arrival-rate or queueing-latency measurements.
- **Check results.** Timed reads check sequence endpoints. After timing, each
  writer's final batch and 32 fixture records are read and fully checked.
  This is sampled integrity checking, not exhaustive correctness testing.
  Normal API errors, payload mismatches, diagnostic output, crashes and
  timeouts invalidate the trial. The default per-trial timeout is 120 seconds,
  including setup/validation. Completed results survive an interrupted suite.

The default 64 MiB work volume exceeds the 8 MiB cache, exercising eviction
and multiple 16 MiB log files. Cache/page/file byte budgets stay fixed when
record size changes. For stable performance comparisons, use the same machine,
filesystem and compiler, keep the machine otherwise idle, and increase
`--work-mib` if trials are shorter than roughly 100 ms. Compare a few focused
workloads before running the full matrix.

Current implementation defects are deliberately not worked around. In
particular, a broken public poll/sync path can fail during fixture preparation;
the runner must report that instead of measuring a substitute implementation.

## Extending and checking the suite

`run.py` owns configuration, scheduling and process isolation; `driver/main.odin`
owns log operations and timing; `report.py` owns aggregation and presentation.
To add an access pattern, add its description to `WORKLOADS`, its dispatch in
the driver, and document its operation and timing semantics here. Keep additional
configuration in the serialized config so comparisons cannot silently pool
incompatible cases. Increment `format_version` if result semantics change.

```sh
odin check ./perf/driver -collection:rifle=./src -vet
python3 -m unittest discover -s perf -p 'test_*.py'
python3 perf/run.py --quick --timeout 15 --fail-fast
```
