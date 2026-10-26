# Driver contract

Every client under test (the Swift driver, the .NET driver, optionally ghz) is a standalone executable that implements
this contract. The orchestrator knows nothing else about a driver. The reference implementation of the scheduling rules is
`Sources/LiveBenchCore/OpenLoop.swift`; the JSON types are in `Sources/LiveBenchCore/DriverContract.swift`.

## Command line

```
<driver> run --scenario <effective.json> --connection <connection string> --out <dir>
<driver> version
```

- `run` executes one trial (warmup, then measure, then drain) of one rate step, writes `result.json` and `histogram.json`
  into `<dir>` (created if missing) and exits 0. Any failure to run at all exits non-zero with a message on stderr; the
  orchestrator records the exit status and the tail of stderr and moves on. Operation errors are not a reason to exit
  non-zero: they are counted in `failed`.
- `--scenario` is an `EffectiveScenario` JSON file (field names below). `--connection` is a KurrentDB connection string,
  used with the client's default settings (no tuning in headline runs).
- `version` prints one `DriverVersion` JSON object on stdout and exits 0.

### `version` output

```json
{ "client": "swift", "clientVersion": "<see below>", "runtime": "swift 6.2" }
```

- `client`: short stable id, the same value as `TrialResult.client` (`swift`, `dotnet`, ...).
- `clientVersion`: Swift driver: env `LIVE_BENCH_SDK_COMMIT` if set, else `git rev-parse HEAD` of the repository
  containing the driver source. .NET driver: the exact pinned `KurrentDB.Client` NuGet version, e.g. `1.2.3`.
- `runtime`: language runtime, free text (`swift 6.2`, `.NET 8.0.x`).

## Input: `EffectiveScenario`

| Field | Type | Meaning |
|---|---|---|
| `cellId` | string | echoed into the result |
| `kind` | string | `appendLatency`, `appendThroughput`, `rebuild`, `persistentSubscription`, `catchUp` |
| `eventSize` | int | bytes of JSON event data (a valid JSON document of exactly this many bytes) |
| `metadataSize` | int | bytes of event metadata (60) |
| `batchSize` | int | events per append (1 for latency, 50 for throughput) |
| `streamCount` | int | number of streams, `<streamPrefix>-<n>` for `n` in `0..<streamCount` |
| `streamPrefix` | string | stream name prefix |
| `category` | string | category of the streams (`$ce-<category>`) |
| `groupName` | string? | persistent subscription group (persistentSubscription only) |
| `consumers` | int? | persistent subscription consumers (RoundRobin); absent means 1 |
| `streamLength` | int? | events per stream (rebuild) |
| `rebuildStreams` | [string]? | stream names to read (rebuild) |
| `catchUpExpectedEvents` | int? | corpus size read in catch-up phase 1 |
| `rate` | number | scheduled operations per second (batches/s for throughput, whole-stream reads/s for rebuild, events/s for subscriptions) |
| `warmupSeconds`, `measureSeconds`, `drainSeconds` | number | phase lengths |
| `deadlineMillis` | int | per-operation deadline |
| `inFlightCap` | int | maximum unaccounted operations |
| `seed` | uint64 | seeds every random choice (stream picks) so clients draw the same sequence |

Unknown fields must be ignored; absent optional fields are `null`/absent.

## Load model (open loop)

Applies to the warmup window and the measure window alike (warmup runs at the step's rate and is discarded; counters,
histogram, CPU and RSS reported in the result cover the measure window only: CPU is the difference of process usage
between the start and end of measure+drain).

1. Operation *i* (0-based) is **due at `start + i / rate`**. Operations are scheduled only while the due instant is before
   `start + duration`. Nothing new is scheduled after that.
2. The scheduler never waits for completions. A slow operation must not delay later ones (no backpressure, no
   coordinated omission).
3. **Latency is measured from `min(scheduled instant, actual launch instant)`** to completion. A late launch is charged
   from the schedule, so scheduler lag counts against the client; an early launch (a waker may fire slightly before the due
   instant) is charged from its launch. Never measure from "RPC start" in the headline (that is `Timing.rpcStart`, for
   tools that cannot do better).
4. **In-flight cap**, checked at launch: if `inFlightCap` operations are outstanding, operation *i* is a **drop** (not
   run, no latency). *Outstanding* means launched with no recorded outcome yet. Exceeding the cap never blocks the
   scheduler.
5. **Deadline** is measured from the scheduled instant: an operation completing at or after `scheduled + deadline` is a
   **timeout**, never a success, even if no timer has fired yet. An operation still outstanding at its deadline is recorded
   as a timeout at that moment and cancelled; its later completion is ignored. A timed-out operation no longer counts
   towards the cap.
6. An operation that throws or returns an error is a **failure**.
7. **Drain**: after the window the driver waits until nothing is outstanding or `start + duration + drain` is reached.
   Everything still outstanding then is a timeout.
8. **Exactly one outcome per scheduled index**: `succeeded + failed + dropped + timedOut == scheduled` (the number of
   indices the schedule produced in the window; about `rate * duration`).
9. **Wake-up**: the scheduler must wake tightly. No OS timer leeway/coalescing (the Swift driver uses a zero-tolerance
   clock sleep plus an overshoot estimate; on .NET avoid `Task.Delay` granularity of ~15 ms on some platforms: use a
   high-resolution timer or a short spin/overshoot compensation). Timer error ends up in the latency, so a sloppy timer
   is charged to the client.
10. **Harness floor**: each driver must be able to report its no-op floor (the same scheduler with an operation that
    returns immediately, p50/p99 at the step's rate). Latencies of two drivers are only comparable if their floors are
    comparable (Swift reference numbers are in the `runOpenLoop` doc comment).

### Percentiles

Percentiles are **ranked over all scheduled attempts**, with failures, drops and timeouts counting as +infinity
(censored). The driver therefore records only the latencies of **successes** in `histogram.json`; the orchestrator ranks
them against `scheduled`. A percentile whose rank falls among non-successes is reported as "> deadline".

## What each kind schedules

| `kind` | One scheduled operation is | Success |
|---|---|---|
| `appendLatency` | append of `batchSize` (1) event(s) to a stream picked uniformly with the seeded RNG | append acknowledged |
| `appendThroughput` | append of `batchSize` (50) events in one call to one stream | append acknowledged |
| `rebuild` | read of one whole stream (picked from `rebuildStreams`, seeded) forward from the start, decoding every event | all `streamLength` events decoded |
| `persistentSubscription` | write of one event (category stream picked uniformly) at `rate` events/s; latency = write to delivery to the subscriber | event delivered (first delivery) and acked |
| `catchUp` | phase 1 is a read of the pre-seeded corpus (no rate; reports `catchUpSeconds`); phase 2 as `persistentSubscription` but with a catch-up subscription on `$ce-<category>` | event delivered |

For subscription kinds the latency is end-to-end (writer scheduled instant to subscriber receipt), the writer is part of
the driver, and the same event must be observed once for `uniqueDeliveries`.

## Output: `result.json` (`TrialResult`)

| Field | Type | Meaning |
|---|---|---|
| `client` | string | same as `version.client` |
| `cellId` | string | echoed from the scenario |
| `targetRate` | number | echoed `rate` |
| `timing` | `"scheduled"` or `"rpcStart"` | latency clock origin (see rule 3) |
| `scheduled` | int | indices scheduled in the measure window |
| `succeeded`, `failed`, `dropped`, `timedOut` | int | outcome counts, sum equals `scheduled` |
| `measuredSeconds` | number | length of the measure window as actually run (scheduling window, not including drain) |
| `cpuUserSeconds`, `cpuSystemSeconds` | number | process CPU consumed during measure + drain (from `getrusage(RUSAGE_SELF)` or equivalent, differenced) |
| `maxRssBytes` | uint64 | peak resident set size of the process, in bytes (`ru_maxrss` is KiB on Linux, bytes on macOS: normalise) |
| `ackEnqueued` | int? | persistent subscription: acks sent by the client; else absent/null |
| `uniqueDeliveries` | int? | subscription kinds: distinct events delivered; else null |
| `redeliveries` | int? | subscription kinds: deliveries of an already seen event; else null |
| `catchUpSeconds` | number? | catch-up: wall time of phase 1 until the last corpus event; else null |
| `validation` | object | see below |

Optional fields may be omitted or `null`.

### `validation`

`{ "expectedEvents": int, "receivedEvents": int, "payloadSizesOk": bool }`. The orchestrator fails the trial if
`expectedEvents != receivedEvents` or `payloadSizesOk` is false.

| `kind` | `expectedEvents` | `receivedEvents` |
|---|---|---|
| `appendLatency`, `appendThroughput` | events acknowledged as written by succeeded appends (`succeeded * batchSize`) | the same events confirmed by the driver's own bookkeeping (equal count unless the driver lost track) |
| `rebuild` | streams read (succeeded reads) `* streamLength` | events decoded |
| `persistentSubscription` | events the writer appended successfully | unique deliveries |
| `catchUp` | phase 1: `catchUpExpectedEvents`; phase 2: events the writer appended successfully (sum both phases) | unique events delivered |

`payloadSizesOk` is true iff every event the driver read or received had `eventSize` bytes of data and `metadataSize`
bytes of metadata (append kinds: true when the driver built payloads of those sizes).

## Output: `histogram.json` (`HistogramFile`)

```json
{ "unit": "us", "buckets": [[valueMicros, count], ...] }
```

- Latencies of **successes only**, whole microseconds, clamped to `1...60_000_000`.
- Each bucket is `[lowestEquivalentValue, count]`: the lowest value that maps to the same histogram bucket (HdrHistogram
  with 1 us lowest value, 60 s highest, 3 significant digits), one entry per non-empty bucket, ascending. A driver that
  does not use HdrHistogram may write exact values with counts; the orchestrator re-records them into a 3-digit histogram.
- The sum of counts equals `succeeded`.

## Process rules

- One process, one trial. No state is carried between trials; the orchestrator pins the process to its CPUs.
- stdout is free for logging; the orchestrator reads only the two files (and `version` stdout).
- Do not write outside `--out`.
