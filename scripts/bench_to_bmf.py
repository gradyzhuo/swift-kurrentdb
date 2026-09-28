#!/usr/bin/env python3
"""Convert package-benchmark JMH output into Bencher Metric Format (BMF).

Usage: bench_to_bmf.py <Current_run.jmh.json> > bmf.json

`swift package benchmark --format jmh` writes one JSON array with an entry per
benchmark. The primary metric is throughput; wall clock and allocation counts
live in `secondaryMetrics`, with units that package-benchmark scales per
benchmark (ns / μs / ms, # / K / M). This script normalises them:

  latency      p50 wall clock in nanoseconds, bounds = p0 and p90
  allocations  p50 `Malloc (total)`, bounds = p0 and p90

Benchmarks without a wall clock metric are skipped; the script fails if no
benchmark was converted so a broken run cannot upload an empty report.
"""

import json
import sys

JMH_PREFIX = "package.benchmark."
WALL_CLOCK = "Time (wall clock)"
MALLOC_TOTAL = "Malloc (total)"

TIME_SCALE = {"ns": 1.0, "μs": 1e3, "µs": 1e3, "us": 1e3, "ms": 1e6, "s": 1e9}
COUNT_SCALE = {"#": 1.0, "K": 1e3, "M": 1e6}


def benchmark_name(jmh_name: str) -> str:
    """Strip the `package.benchmark.<target>.` prefix JMH output adds."""
    if not jmh_name.startswith(JMH_PREFIX):
        return jmh_name
    rest = jmh_name[len(JMH_PREFIX):]
    target, sep, name = rest.partition(".")
    return name if sep else rest


def to_nanoseconds(value: float, unit: str) -> float:
    if unit not in TIME_SCALE:
        raise ValueError(f"unknown time unit {unit!r}")
    return float(value) * TIME_SCALE[unit]


def to_count(value: float, unit: str) -> float:
    if unit not in COUNT_SCALE:
        raise ValueError(f"unknown count unit {unit!r}")
    return float(value) * COUNT_SCALE[unit]


def _measure(metric: dict, scale) -> dict:
    unit = metric["scoreUnit"]
    percentiles = metric["scorePercentiles"]
    return {
        "value": scale(percentiles["50.0"], unit),
        "lower_value": scale(percentiles["0.0"], unit),
        "upper_value": scale(percentiles["90.0"], unit),
    }


def convert(entries: list) -> dict:
    bmf = {}
    for entry in sorted(entries, key=lambda e: benchmark_name(e["benchmark"])):
        secondary = entry.get("secondaryMetrics", {})
        if WALL_CLOCK not in secondary:
            continue
        measures = {"latency": _measure(secondary[WALL_CLOCK], to_nanoseconds)}
        if MALLOC_TOTAL in secondary:
            measures["allocations"] = _measure(secondary[MALLOC_TOTAL], to_count)
        bmf[benchmark_name(entry["benchmark"])] = measures
    return bmf


def main(argv: list) -> int:
    if len(argv) != 2:
        print(f"usage: {argv[0]} <Current_run.jmh.json>", file=sys.stderr)
        return 2
    with open(argv[1], encoding="utf-8") as f:
        entries = json.load(f)
    bmf = convert(entries)
    if not bmf:
        print(f"error: no benchmarks with a wall clock metric in {argv[1]}", file=sys.stderr)
        return 1
    json.dump(bmf, sys.stdout, indent=2, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
