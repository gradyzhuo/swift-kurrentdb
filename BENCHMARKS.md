# Benchmarks

Offline benchmarks for swift-kurrentdb covering client-side code paths that require no server connection.
All benchmarks use [ordo-one/benchmark](https://github.com/ordo-one/benchmark) and are run in **release mode**.

## Environment

Both columns were measured on the same commit on 2026-10-25.

| | macOS | Linux |
|---|---|---|
| **Machine** | Apple M1 Max (arm64), 10 cores, 64 GB | GitHub `ubuntu-latest`, AMD EPYC 9V45 (x86_64), 4 vCPU, 16 GB |
| **OS** | macOS 27.2 (Darwin 27.2.0) | Ubuntu 24.04.5 LTS (6.17.0-1022-azure) |
| **Swift** | 6.4 (swiftlang-6.4.0.34.1) | 6.4.1 (swift-6.4.1-RELEASE) |
| **Build** | Release | Release |
| **Source** | local run | `Benchmarks` workflow, run 40121083776 |

## Results

> `p50` = median wall-clock latency per iteration
> `Malloc` = heap allocations per iteration
> `Instructions` = CPU instructions per iteration (macOS only; Linux needs `perf_event`, which GitHub runners do not expose)
> `*` = lower is better
>
> On Linux the benchmark runtime interposer adds a fixed floor of 16 allocations to every
> benchmark, so a zero-allocation benchmark reports 16 there. Compare Linux `Malloc` minus 16
> with the macOS column. Linux numbers come from a shared 4 vCPU runner and vary between runs;
> treat differences under about 10% as noise.

### EventData

| Benchmark | macOS p50 | macOS Malloc | macOS Instructions | Linux p50 | Linux Malloc |
|---|---|---|---|---|---|
| `EventData/create-raw-data` | 1,167 ns | 1 | 5,935 | 3,555 ns | 17 |
| `EventData/create-codable-model` | 1,208 ns | 2 | 6,799 | 3,545 ns | 18 |
| `EventData/encode-codable-payload` | 3,751 ns | 13 | 34 K | 5,011 ns | 29 |
| `EventData/create-batch-100-raw` | 78 µs | 501 | 911 K | 357 µs | 517 |
| `EventData/create-batch-100-codable` | 52 µs | 201 | 582 K | 342 µs | 217 |

**Observations:**
- Creating a raw `EventData` from `Data` costs ~1.2 µs on macOS with 1 allocation (the internal `Data` copy).
- Using a `Codable` model (`EventData(eventType:model:)`) adds 1 extra allocation to box the model inside the payload. Encoding is deferred until `.data` is read, so construction cost is almost identical to the raw case.
- `encode-codable-payload` (calling `.data` on a `.json` payload) is the full `JSONEncoder().encode()` path and the hot path when serialising events to the wire: ~3.8 µs on macOS, ~5.0 µs on Linux.
- Batch construction of 100 events scales linearly with no unexpected overhead.
- `EventData` construction is about 3× slower on Linux than on macOS for one event and 4.5–6.5× for a batch of 100. The allocation counts match, so this is the cost of swift-foundation's `Data` and `UUID` on that runner rather than extra work in the SDK.

---

### Connection string parsing

| Benchmark | macOS p50 | macOS Malloc | macOS Instructions | Linux p50 | Linux Malloc |
|---|---|---|---|---|---|
| `ClientSettings/parse-single-node` | 9,007 ns | 11 | 118 K | 8,927 ns | 44 |
| `ClientSettings/parse-cluster-seeds` | 20 µs | 29 | 272 K | 18 µs | 70 |

**Observations:**
- The strict RFC 3986 parser (PR #160) parses a single-node connection string in ~9 µs with 11 allocations on macOS. The parser measured on 2026-09-28 took ~400 µs and ~1,240 allocations for the same string.
- Three seeds cost about twice as much as one node.
- Parse once at startup and reuse the `ClientSettings`; there is no reason to parse in a hot path.

---

### Append request encoding

`Append/encode-request/<events>x<payload>` builds the request messages of one append
(`requestMessages()`) and serialises each to bytes, as the gRPC serializer does before
writing them to the stream. The events carry raw `Data` payloads, so JSON encoding is not included.

| Benchmark | macOS p50 | macOS Malloc | macOS Instructions | Linux p50 | Linux Malloc |
|---|---|---|---|---|---|
| `Append/encode-request/1x100B` | 2,751 ns | 6 | 24 K | 2,153 ns | 24 |
| `Append/encode-request/1x4KB` | 2,835 ns | 6 | 25 K | 2,263 ns | 24 |
| `Append/encode-request/1x64KB` | 5,043 ns | 6 | 42 K | 3,085 ns | 24 |
| `Append/encode-request/100x100B` | 89 µs | 204 | 1,156 K | 112 µs | 222 |
| `Append/encode-request/100x4KB` | 104 µs | 204 | 1,292 K | 122 µs | 222 |
| `Append/encode-request/100x64KB` | 284 µs | 204 | 2,939 K | 206 µs | 222 |
| `Append/encode-request/1000x100B` | 878 µs | 2,004 | 11.5 M | 1.23 ms | 2,022 |
| `Append/encode-request/1000x4KB` | 1.01 ms | 2,004 | 12.9 M | 1.32 ms | 2,022 |
| `Append/encode-request/1000x64KB` | 2.19 ms | 2,004 | 29.4 M | 2.14 ms | 2,022 |

**Observations:**
- Each event costs ~0.9 µs and 2 allocations on macOS (~1.2 µs on Linux), plus a fixed 4 allocations per request (6 on Linux, after the floor of 16).
- Payload size changes the time, not the allocations: copying a 64 KB payload into the serialised message adds ~1.3 µs per event on macOS (~0.9 µs on Linux).
- For `Codable` models add `EventData/encode-codable-payload` per event: JSON encoding costs about four times as much as the protobuf encoding around it.

---

### Read response decoding

`Read/decode-response/<events>x<payload>` parses one serialised `ReadResp` per event, as the
server streams them, and turns each into a `Streams.ReadResponse`. `Read/decode-model/<events>`
then decodes the `RecordedEvent`s of such a read into a three-field `Codable` struct with `decode(to:)`.

| Benchmark | macOS p50 | macOS Malloc | macOS Instructions | Linux p50 | Linux Malloc |
|---|---|---|---|---|---|
| `Read/decode-response/1x100B` | 4,667 ns | 9 | 46 K | 3,135 ns | 27 |
| `Read/decode-response/1x4KB` | 4,583 ns | 9 | 47 K | 3,225 ns | 27 |
| `Read/decode-response/1x64KB` | 5,751 ns | 9 | 60 K | 3,685 ns | 27 |
| `Read/decode-response/100x100B` | 321 µs | 900 | 4,329 K | 289 µs | 1,116 |
| `Read/decode-response/100x4KB` | 338 µs | 900 | 4,436 K | 298 µs | 1,116 |
| `Read/decode-response/100x64KB` | 574 µs | 900 | 5,722 K | 380 µs | 1,116 |
| `Read/decode-response/1000x100B` | 3.19 ms | 9,000 | 43.2 M | 2.96 ms | 11,020 |
| `Read/decode-response/1000x4KB` | 3.41 ms | 9,000 | 44.4 M | 3.02 ms | 11,020 |
| `Read/decode-response/1000x64KB` | 5.57 ms | 9,000 | 57.3 M | 4.92 ms | 11,020 |

| Benchmark | macOS p50 | macOS Malloc | macOS Instructions | Linux p50 | Linux Malloc |
|---|---|---|---|---|---|
| `Read/decode-model/1` | 3,417 ns | 12 | 33 K | 2,183 ns | 28 |
| `Read/decode-model/100` | 231 µs | 1,200 | 3,021 K | 183 µs | 1,216 |
| `Read/decode-model/1000` | 2.37 ms | 12,000 | 30.0 M | 1.82 ms | 12,020 |

**Observations:**
- Decoding a response costs ~3.2 µs and 9 allocations per event on macOS (~3.0 µs and 11 allocations on Linux): 2.4–3.6× the time and 4.5–5.5× the allocations of encoding an event for an append.
- Payload size again changes only the time: 64 KB adds ~2.4 µs per event on macOS (~2.0 µs on Linux).
- `decode(to:)` adds ~2.4 µs and 12 allocations per event on macOS (~1.8 µs on Linux).
- Rebuilding an aggregate from 1,000 small events therefore costs ~5.6 ms of client CPU on macOS and ~4.8 ms on Linux. HTTP/2 framing and the per-element cost of the `AsyncSequence` come on top; these benchmarks leave them out.

---

## Summary

| Category | macOS p50 | Linux p50 | Malloc (macOS) | Notes |
|---|---|---|---|---|
| `EventData` (raw) | ~1.2 µs | ~3.6 µs | 1 | Single Data copy |
| `EventData` (Codable) | ~1.2 µs | ~3.5 µs | 2 | Boxes the model; encode deferred |
| Event serialisation | ~3.8 µs | ~5.0 µs | 13 | `JSONEncoder().encode()` path |
| Append request, per event | ~0.9 µs | ~1.2 µs | 2 | Protobuf only; add serialisation for `Codable` models |
| Read response, per event | ~3.2 µs | ~3.0 µs | 9 | Bytes to `ReadResponse` |
| Model decoding, per event | ~2.4 µs | ~1.8 µs | 12 | `RecordedEvent.decode(to:)` |
| Connection string parsing | 9–20 µs | 9–18 µs | 11–29 | Parse once, reuse the result |

---

## Running Benchmarks

### Prerequisites

The benchmark package needs jemalloc for malloc tracking.

```bash
# macOS
brew install jemalloc

# Ubuntu / Debian
sudo apt-get install -y libjemalloc-dev
```

On macOS the `OfflineBenchmarks` target is always declared. On Linux it is
opt-in: set `KURRENTDB_BENCHMARKS=1` for every `swift package` invocation
below, otherwise `Package.swift` leaves the target (and the jemalloc
dependency) out so plain `swift build` keeps working without jemalloc.

### Run all offline benchmarks

```bash
# macOS
PKG_CONFIG_PATH=/opt/homebrew/lib/pkgconfig \
  swift package --disable-sandbox benchmark --target OfflineBenchmarks

# Linux
KURRENTDB_BENCHMARKS=1 \
  swift package --disable-sandbox benchmark --target OfflineBenchmarks
```

Add `--format markdown` to get the tables in the format used by this file.

### Filter by name

`--filter` is a regular expression matched against the whole benchmark name,
so wrap partial names in `.*`.

```bash
# All EventData benchmarks
PKG_CONFIG_PATH=/opt/homebrew/lib/pkgconfig \
  swift package --disable-sandbox benchmark \
  --target OfflineBenchmarks \
  --filter ".*EventData.*"

# Exact benchmark
PKG_CONFIG_PATH=/opt/homebrew/lib/pkgconfig \
  swift package --disable-sandbox benchmark \
  --target OfflineBenchmarks \
  --filter "ClientSettings/parse-single-node"
```

### List available benchmarks

```bash
PKG_CONFIG_PATH=/opt/homebrew/lib/pkgconfig \
  swift package --disable-sandbox benchmark list
```

### Save baseline for regression tracking

```bash
# Save current results as baseline named "main"
PKG_CONFIG_PATH=/opt/homebrew/lib/pkgconfig \
  swift package --disable-sandbox benchmark \
  --target OfflineBenchmarks baseline update main

# Compare against baseline after changes
PKG_CONFIG_PATH=/opt/homebrew/lib/pkgconfig \
  swift package --disable-sandbox benchmark \
  --target OfflineBenchmarks baseline compare main
```

### Linux results via GitHub Actions

The `Benchmarks` workflow (`.github/workflows/benchmarks.yml`) runs the
same suite on `ubuntu-latest`. It runs on every push to `main` and can be
started by hand from the Actions tab. Each run writes the runner
description and the full markdown report to the job summary and uploads
them as the `offline-benchmarks-*` artifact. Numbers are copied into this
file by hand: GitHub-hosted runners do not guarantee identical hardware
between runs, so a person checks a run before it becomes the reference.

### History on Bencher

Every workflow run also uploads its results to
[Bencher](https://bencher.dev/perf/gradyzhuo-s-project), which keeps one
data point per commit and draws them over time. Two measures are tracked
per benchmark:

| Measure | Value | Bounds | Source |
|---|---|---|---|
| `latency` | p50 wall clock, ns | p0 / p90 | `Time (wall clock)` |
| `allocations` | p50 malloc count | p0 / p90 | `Malloc (total)` |

The conversion lives in `scripts/bench_to_bmf.py` (tests in
`scripts/test_bench_to_bmf.py`): the workflow exports a second run in JMH
format, which carries every percentile, and normalises the per-benchmark
units package-benchmark picks (ns / μs, # / K) before upload.

Two thresholds apply to pushes to `main`, and either alert fails the job:

| Measure | Test | Alerts when |
|---|---|---|
| `latency` | t-test, upper boundary 0.99, last 64 runs, at least 10 | the run lands outside the band of recent history |
| `allocations` | percentage, upper boundary 0.01, previous run only | the count grows by more than 1% |

The latency test waits until a benchmark has 10 runs of history. Runners
land on different CPUs, and two runs of the same code differed by up to
63%, so a shorter history gives too narrow a band and alerts on noise.

Allocation counts are deterministic for a given toolchain and runner image:
over 35 runs on `main` every benchmark reported the same count each time,
except when the code under it changed. So the allocation threshold compares
against the previous run alone. The workflow installs the latest Swift 6.4
patch on `ubuntu-latest`, so a new patch release or runner image can shift
the counts too. A deliberate increase or such an environment change alerts
once, and the next run compares against the new count. Runs on other
branches are uploaded without thresholds.

To reproduce the upload locally:

```bash
python3 -m unittest scripts/test_bench_to_bmf.py
swift package --disable-sandbox benchmark --target OfflineBenchmarks --format jmh --path bench-out
python3 scripts/bench_to_bmf.py bench-out/Current_run.jmh.json > bmf.json
```

---

## Live benchmarks

The offline suite above needs no server. The live suite (`Benchmarks/Live`, its own SwiftPM package) runs the SDK
against a real KurrentDB server (`kurrentplatform/kurrentdb:26.2.x`, the tag pinned in
`Benchmarks/Live/config/server.json`) next to the official .NET client (`KurrentDB.Client`) and, for append and
rebuild, [ghz](https://github.com/bojand/ghz) as a transport reference. Local runs, building the drivers and the
command line are in [Benchmarks/Live/README.md](Benchmarks/Live/README.md); what every client must do is in
[Benchmarks/Live/docs/driver-contract.md](Benchmarks/Live/docs/driver-contract.md).

### What runs

Each **cell** is one scenario at one event size, TLS on or off (`Benchmarks/Live/config/cells.json`):

| Scenario | Clients | Measures |
|---|---|---|
| Append latency (batch 1) | Swift, .NET, ghz | latency from scheduled send time at fixed rates |
| Append throughput (batch 50) | Swift, .NET, ghz | the same, in batches per second |
| Persistent subscription | Swift, .NET | from an event's scheduled append to its first receipt, acked on receipt |
| Catch-up subscription | Swift, .NET | catch-up of a seeded category, then live delivery as above |
| Rebuild | Swift, .NET, ghz | whole-stream reads decoding every event (ghz without decoding); one cell per stream length, 10 to 10,000 events |

Headline cells (300 B events, TLS) run the full rate ramp over at least 5 rounds; the appendix (1 KB, 4 KB, TLS off,
four persistent subscription consumers) runs two rates over fewer rounds. Load is an open loop at fixed rates, every
client with the same in-flight cap and per-operation deadline and with its SDK's default client settings. Percentiles
count failed, dropped and timed-out attempts as worse than the deadline, and a step that does not sustain its rate is
never used in a comparison.

Every cell is one job on one `ubuntu-latest` runner (4 vCPU): the server container is pinned to two cores and the
client under test to the other two, and the clients take turns in rotated order over the rounds. The report's
headline is the **ratio** Swift ÷ .NET (p50, p99, client CPU per 1,000 operations, RSS) with a 95% confidence interval
over the rounds; the target is 1.2. Ratios are only published for steps where the server had headroom, and numbers
from different jobs are never divided. The network is loopback, so real network effects are not included.

### How to trigger

The `Live benchmarks` workflow (`.github/workflows/live-benchmarks.yml`) runs:

- **On demand**, from the Actions tab or `gh workflow run live-benchmarks.yml -f cells=<id>,<id>`. The `cells` input
  takes comma-separated cell ids; empty runs every cell.
- **On every release tag**, every cell.
- **Nightly on `main`** (18:00 UTC), the trend job only: every headline cell at one moderate rate, one round, Swift
  only, uploaded to [Bencher](https://bencher.dev/perf/gradyzhuo-s-project) on the testbed `ubuntu-latest-live`. It
  uses the latency t-test of the offline suite (10 runs of history, 99% band of the last 64) but never fails the job
  on an alert: live latency on shared runners is too noisy for a hard threshold.

A comparison run has one job per cell (each under 350 minutes, uploading the artifact `cell-<id>`) and a `merge` job
that turns them into the artifact `live-benchmark-report`: a results bundle `<YYYY-MM-DD>-<server version>/` with
every cell's raw histograms and trial results, `metadata.json` (SDK and harness commits, Swift toolchain, .NET runtime,
`KurrentDB.Client` and ghz versions, server image digest and configuration, runner image and CPU model), the resolved
Swift and .NET dependency graphs, and `report.html`.

### How results land

The workflows commit nothing, matching the offline suite: GitHub-hosted runners differ between runs, so a person
reviews a run before it becomes a reference. To publish one:

1. Download `live-benchmark-report` from the run and check `report.html`.
2. Commit the bundle under `Benchmarks/Live/results/<YYYY-MM-DD>-<server version>/` in a pull request.
3. Once merged, the report is published on the [benchmarks page](https://gradyzhuo.github.io/swift-kurrentdb/benchmarks.html)
   of the GitHub Pages site, and a summary with the link to it is added below.

### Published runs

None yet.
