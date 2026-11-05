#!/usr/bin/env python3
"""Build and run rifle's log benchmarks. Python standard library only."""
import argparse
import datetime as dt
import hashlib
import itertools
import json
import math
import os
from pathlib import Path
import platform
import random
import shutil
import subprocess
import sys
import tempfile
import time

from report import summarize, workload_name

ROOT = Path(__file__).resolve().parent.parent
HERE = Path(__file__).resolve().parent
MIB = 1024 * 1024
WORKLOADS = {
    "append": "single-record appends",
    "batch": "batched ingestion",
    "scan": "batched sequential replay; disjoint reader ranges",
    "random": "uniform single-record reads over a larger-than-cache fixture",
    "hot": "uniform reads over a prewarmed quarter-cache working set",
    "mixed": "random historical reads and single-record appends; ratio set by --read-percent",
    "checkpoint": "batched concurrent ingestion with periodic durable group commit",
}


def positive(value):
    number = int(value)
    if number <= 0:
        raise argparse.ArgumentTypeError("must be positive")
    return number


def numbers(value):
    try:
        return list(dict.fromkeys(positive(x) for x in value.split(",")))
    except (ValueError, argparse.ArgumentTypeError) as exc:
        raise argparse.ArgumentTypeError("expected comma-separated positive integers") from exc


def matrix(args):
    if args.matrix == "full":
        pairs = list(itertools.product(args.sizes, args.threads))
    else:
        pairs = [(size, args.threads[0]) for size in args.sizes]
        pairs += [(args.sizes[0], n) for n in args.threads[1:]]
    configs = [dict(workload=workload, record_bytes=size, threads=threads,
                 batch_records=args.batch, work_bytes=args.work_mib * MIB,
                 dataset_bytes=args.dataset_mib * MIB, cache_bytes=args.cache_mib * MIB,
                 page_bytes=args.page_bytes, file_bytes=args.file_mib * MIB,
                 checkpoint_bytes=args.checkpoint_mib * MIB,
                 sample_every=args.sample_every, seed=args.seed)
            for workload in args.workloads for size, threads in pairs]
    for config in configs:
        if config["workload"] == "mixed":
            config["read_percent"] = args.read_percent
    return configs


def command_output(*args):
    try:
        return subprocess.check_output(args, cwd=ROOT, text=True, stderr=subprocess.DEVNULL).strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def source_hash():
    digest = hashlib.sha256()
    for path in sorted(list((ROOT / "src" / "rifle").glob("*.odin")) +
                       list((HERE / "driver").glob("*.odin"))):
        digest.update(str(path.relative_to(ROOT)).encode())
        digest.update(path.read_bytes())
    return digest.hexdigest()


def metadata(args, build_command):
    cpu = "unknown"
    try:
        cpu = next(line.split(":", 1)[1].strip() for line in Path("/proc/cpuinfo").read_text().splitlines()
                   if line.startswith("model name"))
    except (OSError, StopIteration):
        pass
    return dict(type="metadata", format_version=2, created_utc=dt.datetime.now(dt.timezone.utc).isoformat(),
                platform=platform.platform(), cpu=cpu, logical_cpus=os.cpu_count(),
                affinity=sorted(os.sched_getaffinity(0)) if hasattr(os, "sched_getaffinity") else None,
                odin=command_output(args.odin, "version"), git_commit=command_output("git", "rev-parse", "HEAD"),
                git_status=command_output("git", "status", "--short"), source_sha256=source_hash(),
                build_command=build_command, data_dir=str(args.data_dir),
                filesystem=command_output("df", "-T", str(args.data_dir)),
                options={key: str(value) if isinstance(value, Path) else value for key, value in vars(args).items()},
                thread_model="N client workers plus one polling coordinator",
                planned_trials=len(matrix(args)) * args.repeats)


def validate(args, parser):
    if not 1 <= args.read_percent <= 99:
        parser.error("--read-percent must be between 1 and 99; use append or random for pure workloads")
    if min(args.sizes) < 16:
        parser.error("records must be at least 16 bytes (sequence + writer ID)")
    if max(args.sizes) > 1024 * 1024:
        parser.error("record sizes above 1 MiB are not supported by this harness")
    if args.page_bytes < 4096 or args.page_bytes & (args.page_bytes - 1):
        parser.error("--page-bytes must be a power of two >= 4096")
    if args.cache_mib & (args.cache_mib - 1):
        parser.error("--cache-mib must be a power of two")
    if args.cache_mib * MIB < 4 * args.page_bytes:
        parser.error("cache must contain at least four pages")
    if args.file_mib * MIB % args.page_bytes:
        parser.error("file size must be a multiple of page size")
    # A single request pins all its pages. Leave room for all in-flight batches.
    if max(args.sizes) * args.batch * max(args.threads) > args.cache_mib * MIB // 4:
        parser.error("concurrent batches exceed a quarter of the cache; reduce --batch or increase --cache-mib")
    if args.dataset_mib < 2 * args.cache_mib:
        parser.error("--dataset-mib must be at least twice --cache-mib")
    if args.work_mib * MIB < max(args.sizes) * max(args.threads):
        parser.error("work volume must give each thread at least one record")
    if args.dataset_mib * MIB < max(args.sizes) * max(args.threads):
        parser.error("fixture must give each reader at least one record")
    if args.checkpoint_mib * MIB < max(args.sizes) * max(args.threads):
        parser.error("checkpoint volume must give each thread at least one record")
    if args.dataset_mib + args.work_mib > args.file_mib * 240:
        parser.error("trial would exceed the 256 open-file budget; increase --file-mib")
    if args.sample_every < 0 or args.seed < 1 or args.seed > 2**63 - 1:
        parser.error("sample interval must be nonnegative; seed must be in [1, 2^63-1]")
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        parser.error("--timeout must be finite and positive")


def run_trial(binary, config, args, repetition):
    row = dict(type="trial", config=config, repetition=repetition)
    started = time.monotonic()
    # Cleanup only a directory created by this invocation, including after timeout.
    with tempfile.TemporaryDirectory(prefix="rifle-perf-", dir=args.data_dir) as temporary:
        work = Path(temporary)
        log_dir = work / "log"
        log_dir.mkdir()
        config_file = work / "config.json"
        config_file.write_text(json.dumps(dict(config, log_path=str(log_dir))))
        try:
            result = subprocess.run([str(binary), str(config_file)], text=True, capture_output=True,
                                    timeout=args.timeout, cwd=ROOT)
            if result.returncode:
                row.update(status="failed", error=f"exit {result.returncode}: {result.stderr[-4000:]}")
            else:
                metrics = json.loads(result.stdout)
                expected = config["work_bytes"] // config["record_bytes"]
                if (not metrics["verified"] or metrics["elapsed_ns"] <= 0 or
                        metrics["read_records"] + metrics["write_records"] != expected):
                    raise ValueError("invalid metrics or incomplete operation count")
                row.update(status="ok", metrics=metrics)
            if result.stderr:
                row["stderr"] = result.stderr[-4000:]
                # Library diagnostics can signal IO failure even when the API swallows it.
                if row["status"] == "ok":
                    row.pop("metrics", None)
                    row.update(status="failed", error="driver emitted diagnostics: " + result.stderr[-4000:])
        except subprocess.TimeoutExpired:
            row.update(status="timeout", error=f"exceeded {args.timeout:g}s including setup and verification")
        except (ValueError, KeyError, TypeError) as exc:
            row.update(status="failed", error=f"invalid driver result: {exc}")
    row["process_seconds"] = time.monotonic() - started
    return row


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument("--workloads", type=lambda s: s.split(","), default=list(WORKLOADS))
    parser.add_argument("--sizes", type=numbers, default=[256, 64, 1000, 4096], help="record sizes in bytes; first is sweep baseline")
    parser.add_argument("--threads", type=numbers, default=[1, 2, 4, 8], help="client threads; coordinator is additional")
    parser.add_argument("--matrix", choices=["sweep", "full"], default="sweep", help="vary one axis at a time or take full product")
    parser.add_argument("--repeats", type=positive, default=3)
    parser.add_argument("--work-mib", type=positive, default=64, help="total timed payload bytes across all workers")
    parser.add_argument("--dataset-mib", type=positive, default=32, help="untimed seed/warmup payload")
    parser.add_argument("--cache-mib", type=positive, default=8)
    parser.add_argument("--page-bytes", type=positive, default=8192)
    parser.add_argument("--file-mib", type=positive, default=16)
    parser.add_argument("--batch", type=positive, default=64)
    parser.add_argument("--read-percent", type=int, default=50, help="read share of mixed operations (1-99); remaining operations append")
    parser.add_argument("--checkpoint-mib", type=positive, default=4)
    parser.add_argument("--sample-every", type=int, default=64, help="time every Nth call; 0 disables operation latency sampling")
    parser.add_argument("--seed", type=int, default=12345)
    parser.add_argument("--timeout", type=float, default=120, help="seconds per trial, including setup")
    parser.add_argument("--data-dir", type=Path, default=HERE / ".data", help="directory on the filesystem to benchmark")
    parser.add_argument("--out", type=Path, help="new JSONL result file (never overwritten)")
    parser.add_argument("--odin", default="odin", help="Odin compiler executable")
    parser.add_argument("--quick", action="store_true", help="small smoke run; overrides sizes, threads, repeats and byte budgets")
    parser.add_argument("--list", action="store_true", help="print the matrix without building or running")
    parser.add_argument("--fail-fast", action="store_true")
    args = parser.parse_args()
    if args.quick:
        args.sizes, args.threads, args.repeats = [64, 1000], [1, 2], 1
        args.cache_mib, args.dataset_mib, args.work_mib, args.checkpoint_mib = 1, 4, 4, 1
        args.batch = min(args.batch, 64)
    unknown = set(args.workloads) - WORKLOADS.keys()
    if unknown:
        parser.error(f"unknown workloads: {', '.join(sorted(unknown))}")
    args.workloads = list(dict.fromkeys(args.workloads))
    validate(args, parser)
    configs = matrix(args)
    schedule = [(c, r) for r in range(1, args.repeats + 1) for c in configs]
    random.Random(args.seed).shuffle(schedule)
    print(f"{len(configs)} cases x {args.repeats} repeats = {len(schedule)} trials; N workers + 1 polling coordinator", flush=True)
    if args.list:
        for c in configs:
            print(f"  {workload_name(c):11} {c['record_bytes']:6} B  {c['threads']:2} threads  {WORKLOADS[c['workload']]}")
        return 0
    if platform.system() != "Linux":
        parser.error("rifle currently requires Linux with io_uring")
    if shutil.which(args.odin) is None:
        parser.error(f"Odin compiler not found: {args.odin}")
    args.data_dir = args.data_dir.resolve()
    args.data_dir.mkdir(parents=True, exist_ok=True)
    if args.out is None:
        args.out = HERE / "results" / (dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ") + ".jsonl")
    args.out = args.out.resolve()
    args.out.parent.mkdir(parents=True, exist_ok=True)
    if args.out.exists():
        parser.error(f"output already exists: {args.out}")
    rows = []
    # An invocation-private binary avoids races between concurrent benchmark runs.
    with tempfile.TemporaryDirectory(prefix="rifle-perf-build-") as build_dir:
        binary = Path(build_dir) / "rifle-perf"
        build = [args.odin, "build", str(HERE / "driver"), f"-collection:rifle={ROOT / 'src'}",
                 f"-out:{binary}", "-o:speed", "-vet"]
        subprocess.run(build, cwd=ROOT, check=True)
        with args.out.open("x") as output:
            output.write(json.dumps(metadata(args, build)) + "\n")
            output.flush()
            for number, (config, repetition) in enumerate(schedule, 1):
                print(f"[{number}/{len(schedule)}] {workload_name(config)} {config['record_bytes']} B / "
                      f"{config['threads']}t repeat {repetition} ... ", end="", flush=True)
                row = run_trial(binary, config, args, repetition)
                rows.append(row)
                output.write(json.dumps(row) + "\n")
                output.flush()
                print(row["status"], flush=True)
                if row["status"] != "ok" and args.fail_fast:
                    break
    print()
    summarize(rows)
    print(f"\nRaw results: {args.out}")
    return int(any(row["status"] != "ok" for row in rows))


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\nInterrupted; completed trials remain in the JSONL file.", file=sys.stderr)
        sys.exit(130)
    except (OSError, subprocess.CalledProcessError) as exc:
        print(f"benchmark runner: {exc}", file=sys.stderr)
        sys.exit(1)
