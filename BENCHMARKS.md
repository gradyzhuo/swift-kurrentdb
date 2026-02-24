# Benchmarks

Offline benchmarks for KurrentDB-Swift covering client-side code paths that require no server connection.
All benchmarks use [ordo-one/package-benchmark](https://github.com/ordo-one/package-benchmark) and are run in **release mode**.

## Environment

| | |
|---|---|
| **Machine** | Apple M-series (arm64), 10 cores, 64 GB |
| **OS** | macOS 15 (Darwin 25.3.0) |
| **Swift** | 6.x |
| **Build** | Release |

## Results

> `p50` = median wall-clock latency per iteration
> `Malloc` = heap allocations per iteration
> `Instructions` = CPU instructions per iteration
> `*` = lower is better

### EventData

| Benchmark | p50 | Malloc | Instructions |
|---|---|---|---|
| `EventData/create-raw-data` | 1,583 ns | 1 | 9,007 |
| `EventData/create-codable-model` | 2,167 ns | 2 | 13,000 |
| `EventData/encode-codable-payload` | 8,583 ns | 15 | 62,000 |
| `EventData/create-batch-100-raw` | 81 µs | 501 | 1,031 K |
| `EventData/create-batch-100-codable` | 48 µs | 201 | 574 K |

**Observations:**
- Creating a raw `EventData` from `Data` costs ~1.6 µs with 1 allocation (the internal `Data` copy).
- Using a `Codable` model (`EventData(eventType:model:)`) adds ~600 ns and 1 extra allocation due to `JSONEncoder` initialisation.
- `encode-codable-payload` (calling `.data` on a `.json` payload) costs ~8.6 µs and 15 allocations — this reflects the full `JSONEncoder().encode()` path and is the hot path when serialising events to the wire.
- Batch construction of 100 events scales linearly with no unexpected overhead.

---

### ClientSettings

| Benchmark | p50 | Malloc | Instructions |
|---|---|---|---|
| `ClientSettings/localhost` | 1,333 ns | 2 | 6,415 |
| `ClientSettings/builder-chain` | 1,458 ns | 2 | 7,631 |
| `ClientSettings/parse-single-node` | 324 µs | 1,072 | 2,615 K |
| `ClientSettings/parse-cluster-seeds` | 397 µs | 1,264 | 3,217 K |

**Observations:**
- `ClientSettings.localhost()` and the builder chain are cheap: ~1.3–1.5 µs, 2 allocations. Safe to call at startup or in tests.
- Connection string parsing is comparatively expensive (~324–397 µs, ~1,000+ allocations) due to `RegexBuilder` and `URLComponents` processing. **Parse once and reuse** — do not call `parse(connectionString:)` in hot paths.
- Cluster seed parsing costs ~22% more than single-node due to iterating over 3 endpoints.

---

### Builder Pattern (Options)

| Benchmark | p50 | Malloc | Instructions |
|---|---|---|---|
| `Streams.Append.Options/default` | 541 ns | 0 | 923 |
| `Streams.Append.Options/with-revision` | 583 ns | 0 | 1,408 |
| `Streams.Read.Options/default` | 541 ns | 0 | 930 |
| `Streams.Read.Options/builder-chain` | 625 ns | 0 | 2,833 |

**Observations:**
- All `Options` builders have **zero heap allocations** — `withCopy` operates entirely on stack-allocated value types.
- A 4-step `Read.Options` builder chain (`.backward().startFrom(.end).limit(100).resolveLinks(true)`) costs only 625 ns — effectively free relative to any network I/O.
- The overhead of adding `.revision(expected:)` to an `Append.Options` is ~42 ns (the extra enum branch).

---

### StreamIdentifier

| Benchmark | p50 | Malloc | Instructions |
|---|---|---|---|
| `StreamIdentifier/create` | 542 ns | 0 | 1,013 |

**Observations:**
- `StreamIdentifier` creation is **zero-allocation** — the name string is stored by value.

---

## Summary

| Category | Typical p50 | Malloc | Notes |
|---|---|---|---|
| Options builders | 541–625 ns | 0 | Zero allocations, stack only |
| `StreamIdentifier` | 542 ns | 0 | Zero allocations |
| `EventData` (raw) | ~1.6 µs | 1 | Single Data copy |
| `EventData` (Codable) | ~2.2 µs | 2 | JSONEncoder init overhead |
| `ClientSettings` factory | ~1.3 µs | 2 | Safe to call repeatedly |
| Event serialisation | ~8.6 µs | 15 | `JSONEncoder().encode()` path |
| Connection string parsing | 324–397 µs | 1,000+ | Parse once, reuse the result |

---

## Running Benchmarks

### Prerequisites

```bash
# macOS only — jemalloc is required for malloc tracking
brew install jemalloc
```

### Run all offline benchmarks

```bash
PKG_CONFIG_PATH=/opt/homebrew/lib/pkgconfig \
  swift package --disable-sandbox benchmark --target OfflineBenchmarks
```

### Filter by name

```bash
# All EventData benchmarks
PKG_CONFIG_PATH=/opt/homebrew/lib/pkgconfig \
  swift package --disable-sandbox benchmark \
  --target OfflineBenchmarks \
  --filter "EventData"

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
