"""Tests for benchmark accounting, comparison, failure handling and cleanup."""
import contextlib
import copy
import io
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import subprocess

import report
import run


def trial(seconds=1, status="ok", **config):
    return dict(type="trial", status=status, repetition=1,
                config=dict(workload="batch", record_bytes=256, threads=1, seed=123) | config,
                metrics=dict(elapsed_ns=int(seconds * 1e9), read_records=0, write_records=4000,
                             read_calls=0, write_calls=100, verified=True, checkpoint_calls=0,
                             read_latency=dict(samples=0, p50_ns=0, p95_ns=0, p99_ns=0),
                             write_latency=dict(samples=100, p50_ns=1000, p95_ns=2000, p99_ns=3000),
                             checkpoint_latency=dict(samples=0, p50_ns=0, p95_ns=0, p99_ns=0)))


class ReportTests(unittest.TestCase):
    def test_medians_use_record_counts_and_exclude_failures(self):
        rows = [trial(1), trial(2), trial(3), trial(.001, status="failed")]
        result, = report.aggregate(rows)
        self.assertEqual(result["records_s"], 2000)
        self.assertEqual(result["calls_s"], 50)
        self.assertAlmostEqual(result["mib_s"], 2000 * 256 / 2**20)
        self.assertEqual(result["write_p99_us"], 3)
        self.assertIsNone(result["read_p99_us"])
        self.assertEqual((result["successes"], result["failures"]), (3, 1))

    def test_every_config_knob_separates_results(self):
        self.assertEqual(len(report.aggregate([trial(batch_records=1), trial(batch_records=64)])), 2)

    def test_old_read_heavy_mix_is_not_compared_with_balanced_mix(self):
        old = trial(workload="mixed")
        balanced = trial(workload="mixed", read_percent=50)
        self.assertNotEqual(report.key(old), report.key(balanced))
        self.assertEqual(report.key(old), report.key(trial(workload="mixed", read_percent=90)))
        self.assertEqual(report.workload_name(old["config"]), "mixed-90r")
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            report.summarize([balanced], [old])
        self.assertIn("mixed-50r", output.getvalue())
        self.assertIn("n/a", output.getvalue())

    def test_all_failed_has_no_rates(self):
        entry, = report.aggregate([trial(status="timeout")])
        self.assertNotIn("records_s", entry)
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            report.summarize([trial(status="timeout")])
        self.assertIn("no performance result", output.getvalue())

    def test_comparison_matches_configuration_and_direction(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            report.summarize([trial(1)], [trial(2)])
        self.assertIn("+100.0%", output.getvalue())
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            report.summarize([trial(1, work_bytes=1024)], [trial(2, work_bytes=2048)])
        self.assertIn("n/a", output.getvalue())

    def test_csv_includes_failures_and_missing_latency(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "results.csv"
            report.export_csv([trial(), trial(status="failed", batch_records=1)], path)
            text = path.read_text()
            self.assertIn("failures", text)
            self.assertIn("write_p95_us", text)
            with self.assertRaises(FileExistsError):
                report.export_csv([trial()], path)


class RunnerTests(unittest.TestCase):
    def test_sweep_versus_full_matrix(self):
        args = SimpleNamespace(matrix="sweep", sizes=[64, 1000], threads=[1, 2, 4], workloads=["append", "scan"],
                               batch=64, work_mib=4, dataset_mib=4, cache_mib=1, page_bytes=8192,
                               file_mib=16, checkpoint_mib=1, sample_every=64, seed=123, read_percent=50)
        cases = run.matrix(args)
        self.assertEqual(len(cases), 8)
        self.assertEqual(len({json.dumps(c, sort_keys=True) for c in cases}), 8)
        self.assertEqual({c["work_bytes"] for c in cases}, {4 * run.MIB})
        args.matrix = "full"
        self.assertEqual(len(run.matrix(args)), 12)
        args.workloads = ["mixed", "append"]
        cases = run.matrix(args)
        self.assertTrue(all(c["read_percent"] == 50 for c in cases if c["workload"] == "mixed"))
        self.assertTrue(all("read_percent" not in c for c in cases if c["workload"] == "append"))

    def exercise_trial(self, completion=None, exception=None):
        with tempfile.TemporaryDirectory() as directory:
            args = SimpleNamespace(data_dir=Path(directory), timeout=.01)
            sentinel = Path(directory) / "keep.txt"
            sentinel.write_text("unrelated user file")
            config = trial()["config"] | {"work_bytes": 4000 * 256}
            with patch("run.subprocess.run", return_value=completion, side_effect=exception):
                row = run.run_trial(Path("/unused/driver"), config, args, 1)
            self.assertEqual(list(Path(directory).iterdir()), [sentinel])
            self.assertNotIn("log_path", config)
            return row

    def test_timeout_is_failure_and_cleans_only_trial(self):
        row = self.exercise_trial(exception=subprocess.TimeoutExpired("driver", .01))
        self.assertEqual(row["status"], "timeout")
        self.assertNotIn("metrics", row)

    def test_crash_has_no_metrics(self):
        row = self.exercise_trial(subprocess.CompletedProcess([], -11, "", "crash"))
        self.assertEqual(row["status"], "failed")
        self.assertIn("-11", row["error"])

    def test_success_checks_total_work(self):
        metrics = trial()["metrics"]
        row = self.exercise_trial(subprocess.CompletedProcess([], 0, json.dumps(metrics), ""))
        self.assertEqual(row["status"], "ok")
        metrics = copy.deepcopy(metrics)
        metrics["write_records"] -= 1
        row = self.exercise_trial(subprocess.CompletedProcess([], 0, json.dumps(metrics), ""))
        self.assertEqual(row["status"], "failed")

    def test_library_diagnostics_invalidate_results(self):
        row = self.exercise_trial(subprocess.CompletedProcess([], 0, json.dumps(trial()["metrics"]), "IO error"))
        self.assertEqual(row["status"], "failed")


if __name__ == "__main__":
    unittest.main()
