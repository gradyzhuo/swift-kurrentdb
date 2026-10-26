# Benchmarks

Offline benchmarks for swift-kurrentdb covering client-side code paths that require no server connection.
All benchmarks use [ordo-one/benchmark](https://github.com/ordo-one/benchmark) and are run in **release mode**.

## Environment

Both columns were measured on the same commit on 2026-10-25; the client-stack section on
2026-10-26, on later code (see there).

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
- Rebuilding an aggregate from 1,000 small events therefore costs ~5.6 ms of client CPU on macOS and ~4.8 ms on Linux. HTTP/2 framing and the per-element cost of the response sequence come on top; the client-stack benchmarks below measure the latter.

---

### Client stack against an in-process server

`Client/*` runs a real `KurrentDBClient` against an in-process server
(`Benchmarks/OfflineBenchmarks/InProcessServer.swift`), plugged in through the package-level
`ClientSettings.transportProvider`. Node selection, the retry wrapper, the shared connection, the
generated gRPC client and the response sequences run as they do against a node. The server answers
from responses serialised in advance and never parses a request, but like a node it takes each
request whole before answering, and it fails a call whose request does not carry the expected number
of messages. There are no sockets and no HTTP/2 framing, so what is left is the cost of the client
and of grpc-swift. Setup makes one call and checks its result (a read makes one buffered and one
lazy), so discovery and the connection happen before measuring, and the node stays cached for the
whole run.

`GRPC/*` makes the same calls with the generated gRPC client alone, on the same kind of in-process
connection behind the same `AnyClientTransport`: `Client/*` minus `GRPC/*` is what the SDK adds
above that transport, whose own forwarding (one call per RPC) both include. Both also include one
copy of every message, each way, between the in-process transport's `[UInt8]` and the Posix
transport's bytes type, which a real connection does not make.

Two things these numbers do not show:
- Memory. The in-process transport queues messages without a limit, so the server can run ahead of a
  slow reader. Against a node, the HTTP/2 flow-control window limits how far it can.
- The server's share of a deadline. Requests reach the in-process server without their
  `grpc-timeout` header, so only the client's timer runs; a node runs its own on its own machine.
  Dropping the header copies the request metadata of a call with a deadline, which a real connection
  does not do.

Measured on 2026-10-26 on the code of PR #182: macOS on the machine above, in two runs with the same
allocation counts and p50s at most 9.4% apart (the second run against the first; the tables show the
first); Linux in
[`Benchmarks` run 40282079929](https://github.com/gradyzhuo/swift-kurrentdb/actions/runs/40282079929)
(AMD EPYC 7763, 4 vCPU, Ubuntu 26.04).

| Benchmark | macOS p50 | macOS Malloc | macOS Instructions | Linux p50 | Linux Malloc |
|---|---|---|---|---|---|
| `Client/append/1x100B` | 58 µs | 110 | 623 K | 142 µs | 122 |
| `Client/append/100x100B` | 299 µs | 1,107 | 4,841 K | 576 µs | 823 |
| `Client/append-with-deadline/1x100B` | 70 µs | 129 | 709 K | 208 µs | 141 |
| `Client/read-buffered/1x100B` | 62 µs | 107 | 655 K | 160 µs | 130 |
| `Client/read-buffered/100x100B` | 730 µs | 1,610 | 10.2 M | 1.23 ms | 1,636 |
| `Client/read-buffered/1000x100B` | 6.54 ms | 15,119 | 95.8 M | 10.97 ms | 15,151 |
| `Client/read-lazy/1x100B` | 68 µs | 117 | 755 K | 199 µs | 139 |
| `Client/read-lazy/100x100B` | 996 µs | 1,808 | 12.7 M | 2.62 ms | 1,836 |
| `Client/read-lazy/1000x100B` | 9.27 ms | 17,114 | 122.2 M | 24.92 ms | 18,015 |

| Benchmark | macOS p50 | macOS Malloc | macOS Instructions | Linux p50 | Linux Malloc |
|---|---|---|---|---|---|
| `GRPC/append/1x100B` | 52 µs | 98 | 593 K | 123 µs | 105 |
| `GRPC/append/100x100B` | 284 µs | 996 | 4,571 K | 479 µs | 708 |
| `GRPC/read/1x100B` | 50 µs | 85 | 570 K | 128 µs | 101 |
| `GRPC/read/100x100B` | 521 µs | 1,479 | 7,721 K | 830 µs | 1,496 |
| `GRPC/read/1000x100B` | 4.92 ms | 14,085 | 72.0 M | 6.95 ms | 14,109 |

**Observations:**
- Most of a one-event call is grpc-swift's: a one-event append takes 58 µs through the client and 52 µs with gRPC alone on macOS (142 µs and 123 µs on Linux). The SDK's per-call work (node selection, the retry wrapper, the connection lease, the call metadata and, for a read, the response stream) adds 12 allocations to it (17 on Linux) and 22 to a one-event read (29). These are totals for one event; each further event adds its own share.
- Each further appended event costs ~2.4–2.6 µs and 10 allocations through the client on macOS, and ~2.3–2.4 µs and 9 with gRPC alone: the SDK adds 1 allocation per event on both systems, and on macOS a time within run-to-run noise.
- Each event of a buffered read costs ~6.5–6.6 µs and 15 allocations on macOS. gRPC alone costs ~4.6–4.9 µs and 14: protobuf decoding plus the in-process transport and its copy. The SDK adds ~1.6–2.0 µs and 1 allocation (~4.0 µs and 1 on Linux).
- A lazy read costs ~2.6–2.7 µs and 2 allocations more per event than a buffered one on macOS: each element waits in the hand-off for the iterating task instead of being queued. That is the price of handing over one element at a time. On Linux the hand-off is the most scheduling-sensitive number: ~14 µs per event in this run, ~16 µs in run 40279300762 on an Intel Xeon Platinum 8573C.
- A default deadline adds ~12–13 µs and 19 allocations to a call on macOS (~66 µs and 19 on Linux): grpc-swift runs every call it bounds in a task group next to a timer task. No server timer is in these numbers, since the in-process server never sees the deadline; the copy of the request metadata that the in-process connection makes to drop the header is.
- These benchmarks allocate on several concurrent tasks, so their counts depend on scheduling. On the 4-vCPU Linux runner a lazy read's count per iteration spreads over 10–11% in the runs above (each element either finds the consumer waiting or suspends in the hand-off), so its Linux `Malloc` is a median of two modes. Bencher records them without a threshold (see [History on Bencher](#history-on-bencher)).

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
| Client call, one event | ~58 µs | ~142 µs | 110 | In-process; gRPC alone: ~52 µs (~123 µs on Linux) |
| Buffered read, per event | ~6.5 µs | ~10.8 µs | 15 | gRPC alone: ~4.7 µs and 14 on macOS |
| Lazy read, per event | ~9.2 µs | ~25 µs | 17 | The hand-off per element; scheduling-sensitive on Linux |
| Default deadline, per call | +12 µs | +66 µs | +19 | grpc-swift's timer task, client side |

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
data point per commit and draws them over time. Each benchmark has a
latency and an allocation measure:

| Measure | Value | Bounds | Source |
|---|---|---|---|
| `latency` | p50 wall clock, ns | p0 / p90 | `Time (wall clock)` |
| `allocations` | p50 malloc count | p0 / p90 | `Malloc (total)` |
| `allocations-concurrent` | p50 malloc count of `Client/*` and `GRPC/*` | p0 / p90 | `Malloc (total)` |

The conversion is `bench-to-bmf` in the `scripts/` package (tests in
`scripts/Tests/ToolingTests`): the workflow exports a second run in JMH
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
patch on `ubuntu-24.04`, so a new patch release or runner image can shift
the counts too. A deliberate increase or such an environment change alerts
once, and the next run compares against the new count. Runs on other
branches are uploaded without thresholds.

The client-stack benchmarks (`Client/*`, `GRPC/*`) are the exception: they
allocate on several concurrent tasks, so their counts depend on scheduling.
Most move by an allocation or two between runs, but on the 4-vCPU runner a
lazy read's count per iteration spreads over about 10%, depending on whether
each element finds the consumer waiting, and its median moves with the mix.
`scripts/bench_to_bmf.py` therefore reports them as `allocations-concurrent`,
which keeps the history but has no threshold; the latency test still covers
these benchmarks.

To reproduce the upload locally:

```bash
swift test --package-path scripts --filter BenchToBMFTests
swift package --disable-sandbox benchmark --target OfflineBenchmarks --format jmh --path bench-out
swift run --package-path scripts bench-to-bmf bench-out/Current_run.jmh.json > bmf.json
```
