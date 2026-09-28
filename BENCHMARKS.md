# Benchmarks

Offline benchmarks for swift-kurrentdb covering client-side code paths that require no server connection.
All benchmarks use [ordo-one/benchmark](https://github.com/ordo-one/benchmark) and are run in **release mode**.

## Environment

Both columns were measured on the same commit with Swift 6.4 on 2026-09-28.

| | macOS | Linux |
|---|---|---|
| **Machine** | Apple M1 Max (arm64), 10 cores, 64 GB | GitHub `ubuntu-latest`, AMD EPYC 9V74 (x86_64), 4 vCPU, 16 GB |
| **OS** | macOS 27.0 (Darwin 27.0.0) | Ubuntu 24.04.5 LTS (6.17.0-azure) |
| **Swift** | 6.4 (swiftlang-6.4.0.34.1) | 6.4 (swift-6.4-RELEASE) |
| **Build** | Release | Release |
| **Source** | local run | `Benchmarks` workflow, run 36375693340 |

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
| `EventData/create-raw-data` | 1,125 ns | 1 | 5,911 | 3,635 ns | 17 |
| `EventData/create-codable-model` | 1,167 ns | 2 | 6,891 | 3,817 ns | 18 |
| `EventData/encode-codable-payload` | 3,459 ns | 13 | 34 K | 5,779 ns | 29 |
| `EventData/create-batch-100-raw` | 73 µs | 501 | 906 K | 365 µs | 517 |
| `EventData/create-batch-100-codable` | 51 µs | 201 | 581 K | 337 µs | 217 |

**Observations:**
- Creating a raw `EventData` from `Data` costs ~1.1 µs on macOS with 1 allocation (the internal `Data` copy).
- Using a `Codable` model (`EventData(eventType:model:)`) adds 1 extra allocation to box the model inside the payload. Encoding is deferred until `.data` is read, so construction cost is almost identical to the raw case.
- `encode-codable-payload` (calling `.data` on a `.json` payload) is the full `JSONEncoder().encode()` path and the hot path when serialising events to the wire: ~3.5 µs on macOS, ~5.8 µs on Linux.
- Batch construction of 100 events scales linearly with no unexpected overhead.
- `EventData` construction is 3–5× slower on Linux than on macOS. The allocation counts match, so this is the cost of swift-foundation's `Data` and `UUID` on that runner rather than extra work in the SDK.

---

### ClientSettings

| Benchmark | macOS p50 | macOS Malloc | macOS Instructions | Linux p50 | Linux Malloc |
|---|---|---|---|---|---|
| `ClientSettings/localhost` | 875 ns | 2 | 3,891 | 350 ns | 18 |
| `ClientSettings/builder-chain` | 959 ns | 2 | 5,399 | 601 ns | 18 |
| `ClientSettings/parse-single-node` | 396 µs | 1,242 | 3,445 K | 242 µs | 1,247 |
| `ClientSettings/parse-cluster-seeds` | 431 µs | 1,313 | 3,717 K | 268 µs | 1,318 |

**Observations:**
- `ClientSettings.localhost()` and the builder chain are cheap: under 1 µs, 2 allocations. Safe to call at startup or in tests.
- Connection string parsing is comparatively expensive (hundreds of µs, ~1,200+ allocations) due to `RegexBuilder` and `URLComponents` processing. **Parse once and reuse** — do not call `parse(connectionString:)` in hot paths.
- Cluster seed parsing costs ~10% more than single-node due to iterating over 3 endpoints.

---

### Builder Pattern (Options)

| Benchmark | macOS p50 | macOS Malloc | macOS Instructions | Linux p50 | Linux Malloc |
|---|---|---|---|---|---|
| `Streams.Append.Options/default` | 584 ns | 0 | 965 | 110 ns | 16 |
| `Streams.Append.Options/with-revision` | 625 ns | 0 | 908 | 110 ns | 16 |
| `Streams.Read.Options/default` | 584 ns | 0 | 942 | 110 ns | 16 |
| `Streams.Read.Options/configure-chain` | 584 ns | 0 | 852 | 110 ns | 16 |

**Observations:**
- All `Options` values have **zero heap allocations** — the `inout` configuration closure mutates a stack-allocated value type.
- Configuring `Read.Options` with four settings (direction, revision, limit, resolve links) costs no more than the default — effectively free relative to any network I/O.
- The macOS wall-clock figures for these sit at the timer's resolution (about 42 ns per tick), so the differences between rows are not significant. Instruction counts are the better signal.

---

### StreamIdentifier

| Benchmark | macOS p50 | macOS Malloc | macOS Instructions | Linux p50 | Linux Malloc |
|---|---|---|---|---|---|
| `StreamIdentifier/create` | 625 ns | 0 | 948 | 110 ns | 16 |

**Observations:**
- `StreamIdentifier` creation is **zero-allocation** — the name string is stored by value.

---

## Summary

| Category | macOS p50 | Linux p50 | Malloc (macOS) | Notes |
|---|---|---|---|---|
| Options builders | ~600 ns | ~110 ns | 0 | Zero allocations, stack only |
| `StreamIdentifier` | ~600 ns | ~110 ns | 0 | Zero allocations |
| `EventData` (raw) | ~1.1 µs | ~3.6 µs | 1 | Single Data copy |
| `EventData` (Codable) | ~1.2 µs | ~3.8 µs | 2 | Boxes the model; encode deferred |
| `ClientSettings` factory | ~0.9 µs | ~0.4 µs | 2 | Safe to call repeatedly |
| Event serialisation | ~3.5 µs | ~5.8 µs | 13 | `JSONEncoder().encode()` path |
| Connection string parsing | 396–431 µs | 242–268 µs | 1,200+ | Parse once, reuse the result |

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
