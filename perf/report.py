#!/usr/bin/env python3
"""Pretty-print, export CSV, or compare rifle benchmark JSONL files."""
import argparse
import csv
import json
from pathlib import Path
import statistics
import sys


def load(path):
    rows = []
    metadata = {}
    with Path(path).open() as source:
        for number, line in enumerate(source, 1):
            try:
                row = json.loads(line)
            except ValueError as exc:
                raise ValueError(f"{path}:{number}: invalid JSON (possibly interrupted write)") from exc
            if row.get("type") == "metadata":
                metadata = row
            elif row.get("type") == "trial":
                rows.append(row)
    if metadata.get("format_version") not in (1, 2):
        raise ValueError(f"{path}: unsupported or missing result format version")
    return metadata, rows


def normalized_config(config):
    config = dict(config)
    if config["workload"] == "mixed":
        # Version 1 had a fixed 90%-read mix. Keep old results accurately labelled.
        config.setdefault("read_percent", 90)
    return config


def workload_name(config):
    if config["workload"] == "mixed":
        return f"mixed-{config.get('read_percent', 90)}r"
    return config["workload"]


def key(row):
    # Every workload knob participates, so incompatible trials cannot be pooled.
    return json.dumps(normalized_config(row["config"]), sort_keys=True)


def rate(row, field):
    return row["metrics"][field] * 1e9 / row["metrics"]["elapsed_ns"]


def aggregate(rows):
    grouped = {}
    for row in rows:
        grouped.setdefault(key(row), []).append(row)
    result = []
    for identity, trials in grouped.items():
        config = normalized_config(trials[0]["config"])
        good = [r for r in trials if r["status"] == "ok"]
        entry = dict(config=config, identity=identity, trials=len(trials), successes=len(good),
                     failures=len(trials) - len(good))
        if good:
            records = [rate(r, "read_records") + rate(r, "write_records") for r in good]
            median = statistics.median(records)
            entry.update(records_s=median, mib_s=median * config["record_bytes"] / 2**20,
                         calls_s=statistics.median(rate(r, "read_calls") + rate(r, "write_calls") for r in good),
                         read_records_s=statistics.median(rate(r, "read_records") for r in good),
                         write_records_s=statistics.median(rate(r, "write_records") for r in good),
                         spread_pct=100 * (max(records) - min(records)) / median,
                         elapsed_ms=statistics.median(r["metrics"]["elapsed_ns"] / 1e6 for r in good))
            for operation in ("read", "write", "checkpoint"):
                latencies = [r["metrics"][operation + "_latency"] for r in good]
                entry[operation + "_samples"] = sum(v["samples"] for v in latencies)
                for percentile in ("p50", "p95", "p99"):
                    values = [v[percentile + "_ns"] / 1000 for v in latencies if v["samples"]]
                    entry[f"{operation}_{percentile}_us"] = statistics.median(values) if values else None
        result.append(entry)
    return sorted(result, key=lambda e: (e["config"]["workload"], e["config"].get("read_percent", 0), e["config"]["record_bytes"], e["config"]["threads"]))


def latency_text(entry, operation):
    value = entry.get(operation + "_p99_us")
    return "-" if value is None else f"{value:,.1f}"


def summarize(rows, baseline=None):
    entries = aggregate(rows)
    previous = {e["identity"]: e for e in aggregate(baseline or [])}
    print("Throughput: medians of successful trials. Latency: median trial p99, microseconds per API call.")
    print("N = client workers; one additional coordinator polls IO. MiB/s counts logical payload, not disk traffic.")
    if any(e["config"]["workload"] == "mixed" for e in entries):
        print("mixed-Nr = N% reads / (100-N)% appends, by operation count.")
    header = (f"{'workload':11} {'bytes':>6} {'N':>3} {'ok/all':>7} {'Mrec/s':>9} {'MiB/s':>10} "
              f"{'Kcall/s':>10} {'spread%':>8} {'read99':>9} {'write99':>9} {'sync99':>9}")
    if baseline is not None:
        header += f" {'vs base':>9}"
    print(header)
    print("-" * len(header))
    for entry in entries:
        cfg = entry["config"]
        text = f"{workload_name(cfg):11} {cfg['record_bytes']:6} {cfg['threads']:3} {entry['successes']:3}/{entry['trials']:<3}"
        if not entry["successes"]:
            print(text + "  FAILED (no performance result)")
            continue
        text += (f" {entry['records_s'] / 1e6:9.3f} {entry['mib_s']:10.1f} {entry['calls_s'] / 1000:10.1f}"
                 f" {entry['spread_pct']:8.1f} {latency_text(entry, 'read'):>9}"
                 f" {latency_text(entry, 'write'):>9} {latency_text(entry, 'checkpoint'):>9}")
        if baseline is not None:
            old = previous.get(entry["identity"])
            text += (f" {100 * (entry['records_s'] / old['records_s'] - 1):+8.1f}%"
                     if old and old["successes"] else f" {'n/a':>9}")
        print(text)
    print("spread% = (max - min) / median; one repeat cannot estimate noise. '-' = no samples.")
    if any(e.get("elapsed_ms", 1000) < 100 for e in entries):
        print("Some trials took <100 ms: use more --work-mib for performance conclusions.")
    if any(e.get(op + "_samples", 1000) < 100 for e in entries for op in ("read", "write")
           if e.get(op + "_p99_us") is not None):
        print("Some operation latencies have <100 samples: p99 is only a rough indication.")
    mixed = [e for e in entries if e["config"]["workload"] == "mixed" and e["successes"]]
    if mixed:
        print("\nMixed workload breakdown (median records/s):")
        for e in mixed:
            print(f"  {workload_name(e['config'])} {e['config']['record_bytes']} B / {e['config']['threads']}t: "
                  f"read {e['read_records_s']:,.0f}; write {e['write_records_s']:,.0f}")
    failures = [r for r in rows if r["status"] != "ok"]
    if failures:
        print(f"\n{len(failures)} failed/timed-out trials; successful subsets are not complete benchmark results.")
        for row in failures[:5]:
            cfg = row["config"]
            error = row.get("error", row["status"]).replace("\n", " ")
            print(f"  {workload_name(cfg)} {cfg['record_bytes']} B/{cfg['threads']}t: {error[:250]}")
        if len(failures) > 5:
            print("  See JSONL for remaining errors.")


def export_csv(rows, destination):
    entries = aggregate(rows)
    flattened = []
    for entry in entries:
        flattened.append({**entry["config"], **{k: v for k, v in entry.items() if k not in ("config", "identity")}})
    fields = list(dict.fromkeys(k for row in flattened for k in row))
    with Path(destination).open("x", newline="") as target:
        writer = csv.DictWriter(target, fieldnames=fields)
        writer.writeheader()
        writer.writerows(flattened)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("results", type=Path)
    parser.add_argument("--baseline", type=Path, help="compare matching workload configurations; positive means faster")
    parser.add_argument("--csv", type=Path, help="export aggregate data, including p50/p95/p99 and read/write rates")
    args = parser.parse_args()
    metadata, rows = load(args.results)
    baseline = None
    print(f"{metadata.get('created_utc', '?')} | {metadata.get('cpu', '?')} | {metadata.get('odin', '?')}")
    planned = metadata.get("planned_trials", len(rows))
    if len(rows) != planned:
        print(f"Incomplete suite: {len(rows)} of {planned} planned trials recorded.")
    if args.baseline:
        old_metadata, baseline = load(args.baseline)
        changed = [k for k in ("cpu", "platform", "odin", "affinity", "data_dir") if metadata.get(k) != old_metadata.get(k)]
        if changed:
            print("Comparison environment differs: " + ", ".join(changed))
    summarize(rows, baseline)
    if args.csv:
        export_csv(rows, args.csv)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError) as exc:
        print(f"report: {exc}", file=sys.stderr)
        sys.exit(1)
