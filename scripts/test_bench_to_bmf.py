#!/usr/bin/env python3
"""Tests for bench_to_bmf.py (run with `python3 -m unittest scripts/test_bench_to_bmf.py`)."""

import json
import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bench_to_bmf  # noqa: E402


def metric(unit, p0, p50, p90, score=None):
    return {
        "scoreUnit": unit,
        "score": score if score is not None else p50,
        "scorePercentiles": {"0.0": p0, "50.0": p50, "90.0": p90, "100.0": p90},
    }


def entry(name, wall=None, mallocs=None):
    secondary = {}
    if wall is not None:
        secondary["Time (wall clock)"] = wall
    if mallocs is not None:
        secondary["Malloc (total)"] = mallocs
    return {
        "benchmark": f"package.benchmark.OfflineBenchmarks.{name}",
        "mode": "thrpt",
        "primaryMetric": metric("# / s", 1.0, 2.0, 3.0),
        "secondaryMetrics": secondary,
    }


class BenchmarkNameTests(unittest.TestCase):
    def test_strips_jmh_package_prefix(self):
        self.assertEqual(
            bench_to_bmf.benchmark_name("package.benchmark.OfflineBenchmarks.EventData/create-raw-data"),
            "EventData/create-raw-data",
        )

    def test_keeps_name_without_prefix(self):
        self.assertEqual(bench_to_bmf.benchmark_name("EventData/create-raw-data"), "EventData/create-raw-data")


class UnitScalingTests(unittest.TestCase):
    def test_time_units_scale_to_nanoseconds(self):
        self.assertEqual(bench_to_bmf.to_nanoseconds(0.584, "μs"), 584.0)
        self.assertEqual(bench_to_bmf.to_nanoseconds(0.584, "µs"), 584.0)  # micro sign variant
        self.assertEqual(bench_to_bmf.to_nanoseconds(0.584, "us"), 584.0)
        self.assertEqual(bench_to_bmf.to_nanoseconds(2.5, "ms"), 2_500_000.0)
        self.assertEqual(bench_to_bmf.to_nanoseconds(1.25, "s"), 1_250_000_000.0)
        self.assertEqual(bench_to_bmf.to_nanoseconds(917, "ns"), 917.0)

    def test_unknown_time_unit_is_an_error(self):
        with self.assertRaises(ValueError):
            bench_to_bmf.to_nanoseconds(1, "ks")

    def test_count_units_scale_to_plain_numbers(self):
        self.assertEqual(bench_to_bmf.to_count(1242, "#"), 1242.0)
        self.assertEqual(bench_to_bmf.to_count(3.5, "K"), 3500.0)
        self.assertEqual(bench_to_bmf.to_count(2, "M"), 2_000_000.0)

    def test_unknown_count_unit_is_an_error(self):
        with self.assertRaises(ValueError):
            bench_to_bmf.to_count(1, "G")


class ConvertTests(unittest.TestCase):
    def test_latency_uses_p50_with_p0_and_p90_bounds_in_nanoseconds(self):
        bmf = bench_to_bmf.convert([entry("StreamIdentifier/create", wall=metric("μs", 0.5, 0.584, 0.666))])
        self.assertEqual(
            bmf["StreamIdentifier/create"]["latency"],
            {"value": 584.0, "lower_value": 500.0, "upper_value": 666.0},
        )

    def test_allocations_use_p50_and_bounds(self):
        bmf = bench_to_bmf.convert(
            [entry("ClientSettings/parse-single-node", wall=metric("μs", 1, 2, 3), mallocs=metric("#", 1240, 1242, 1243))]
        )
        self.assertEqual(
            bmf["ClientSettings/parse-single-node"]["allocations"],
            {"value": 1242.0, "lower_value": 1240.0, "upper_value": 1243.0},
        )

    def test_benchmark_without_wall_clock_is_skipped(self):
        bmf = bench_to_bmf.convert([entry("NoWall", mallocs=metric("#", 0, 0, 0))])
        self.assertEqual(bmf, {})

    def test_missing_mallocs_only_omits_that_measure(self):
        bmf = bench_to_bmf.convert([entry("OnlyWall", wall=metric("ns", 1, 2, 3))])
        self.assertEqual(list(bmf["OnlyWall"].keys()), ["latency"])

    def test_output_is_sorted_by_benchmark_name(self):
        bmf = bench_to_bmf.convert(
            [entry("Zeta/x", wall=metric("ns", 1, 2, 3)), entry("Alpha/y", wall=metric("ns", 1, 2, 3))]
        )
        self.assertEqual(list(bmf.keys()), ["Alpha/y", "Zeta/x"])


class CliTests(unittest.TestCase):
    def test_cli_reads_file_and_writes_json_to_stdout(self):
        with tempfile.NamedTemporaryFile("w", suffix=".jmh.json", delete=False) as f:
            json.dump([entry("A/b", wall=metric("ns", 1, 2, 3))], f)
        try:
            script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bench_to_bmf.py")
            out = subprocess.run([sys.executable, script, f.name], capture_output=True, text=True, check=True)
            self.assertEqual(json.loads(out.stdout), {"A/b": {"latency": {"value": 2.0, "lower_value": 1.0, "upper_value": 3.0}}})
        finally:
            os.unlink(f.name)

    def test_cli_fails_when_no_benchmark_converted(self):
        with tempfile.NamedTemporaryFile("w", suffix=".jmh.json", delete=False) as f:
            json.dump([], f)
        try:
            script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bench_to_bmf.py")
            out = subprocess.run([sys.executable, script, f.name], capture_output=True, text=True)
            self.assertNotEqual(out.returncode, 0)
            self.assertIn("no benchmarks", out.stderr)
        finally:
            os.unlink(f.name)


if __name__ == "__main__":
    unittest.main()
