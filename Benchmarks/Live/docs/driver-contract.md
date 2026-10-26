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

Applies to the warmup window and the measure window alike. Warmup runs at the step's rate and its outcomes are
discarded. Counters and histogram in the result cover the measure window only. CPU is the delta of process CPU time
between the start of measure and the end of drain. `maxRssBytes` is the process-lifetime peak resident set size
(`ru_maxrss`, not a delta; includes warmup); a .NET driver must report its process peak too (`Process.PeakWorkingSet64`),
not a managed-heap figure.

### Warmup isolation

Warmup never touches measured data. Warmup streams are named `<streamPrefix>w-<n>` and the warmup category is
`<category>w` (that is, `streamPrefix + "w"` and `category + "w"`, then `-<n>` as usual). Warmup appends go only to
those streams; warmup reads (rebuild) use the same shape against `<streamPrefix>w-*` streams; warmup subscriptions
(persistent and catch-up) use the `$ce-<category>w` stream. The harness seeds whatever warmup data a kind needs before
`run`, exactly as for the measured data. For persistent subscriptions the harness also creates a second group for the
warmup category; the driver does not create groups (see below). Measured streams, the measured category and the measured
group are untouched until the measure window starts.

### Common client settings

- Default client settings and default client options everywhere (headline runs).
- Appends use expected revision **any** (no optimistic concurrency).
- Link resolution (`resolveLinkTos`) must be **explicitly enabled** wherever a `$ce-` stream is read or subscribed
  (catch-up and persistent subscription), for every client: both SDKs default it to off, and without it only link events
  arrive.

### Random choices

All random choices use **splitmix64 seeded with `seed`**, one draw per operation index, in index order (operation *i*
uses draw *i*, whether or not the operation is later dropped, so every client draws the same sequence):

```
state = seed
draw(): state = state + 0x9E3779B97F4A7C15            (mod 2^64)
        z = state
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9      (mod 2^64)
        z = (z ^ (z >> 27)) * 0x94D049BB133111EB      (mod 2^64)
        return z ^ (z >> 31)
```

The stream for operation *i* is index `z % streamCount`, i.e. `<streamPrefix>-<z % streamCount>` for append and
persistent-subscription/catch-up writes. Rebuild picks `rebuildStreams[z % rebuildStreams.count]`. Warmup uses the same
generator, restarted at `state = seed`, with the `w` names.

### Event bytes

Every appended event has:

- event type `BenchEvent`, content type `application/json` (data and metadata are both JSON);
- data of exactly `eventSize` bytes and metadata of exactly `metadataSize` bytes, built by the following function;
- event index `k = i * batchSize + j` for event `j` (0-based) of operation `i`.

`make(size, k, seed')` returns the ASCII bytes `{"i":<k>,"p":"` + `fillerCount` filler bytes + `"}`, where
`<k>` is decimal, `fillerCount = size - len(prefix) - len(suffix)` (prefix `{"i":<k>,"p":"`, suffix `"}`; size is
always large enough). Filler: `alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"` (62 bytes);

```
state = seed' XOR (k * 0xBF58476D1CE4E5B9)            (mod 2^64)
repeat fillerCount times:
    state = state + 0x9E3779B97F4A7C15                (mod 2^64)
    z = state
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9          (mod 2^64)
    z = (z ^ (z >> 27)) * 0x94D049BB133111EB          (mod 2^64)
    z = z ^ (z >> 31)
    append alphabet[z % 62]
```

Data uses `seed' = seed`; metadata uses `seed' = seed + 0x9E3779B97F4A7C15 (mod 2^64)`. Reference:
`Sources/LiveBenchCore/Payload.swift`.

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
| `persistentSubscription` | append of one event (stream picked per "Random choices") at `rate` events/s; latency = writer's `min(scheduled, launch)` to the subscriber's first receipt of that event | event received (first delivery) |
| `catchUp` | see "Catch-up" below | event received by the live phase |

For subscription kinds the writer is part of the driver (same process, same open-loop rules, expected revision any).
The append outcome is the operation outcome for accounting; the latency of a succeeded operation is taken at the
subscriber's receipt: origin is `min(scheduled instant of the append, actual launch of the append)` (rule 3), end is the
first receipt of that event (matched by the event's index `k`). An append that succeeds but whose event is never received
by `scheduled + deadline` is a timeout (rule 5). Receipts of an event already received count as `redeliveries`.

### Persistent subscription

- The harness creates the group before `run` (resolve links on, RoundRobin, start from the beginning of
  `$ce-<category>`; name in `groupName`). The driver must not create, update or delete it.
- The driver connects `consumers` (absent = 1) consumers to the group in the same process, with default client
  options, and **acks each event on receipt** (one ack per event; `ackEnqueued` counts acks handed to the client).
- `uniqueDeliveries` counts distinct events across all consumers.

### Catch-up

Phase 1 reads the pre-seeded corpus of `catchUpExpectedEvents` events in `$ce-<category>` through a **catch-up
subscription from the start** of that stream (not a stream read), with link resolution enabled.

- Order: warmup first (it only exercises the live append path and a subscription on `$ce-<category>w`; no corpus),
  then phase 1, then phase 2's measure window.
- `catchUpSeconds` starts immediately before the subscribe call and stops when the `catchUpExpectedEvents`-th event has
  been received (wall clock, monotonic).
- Phase 1 is not open loop and contributes nothing to the outcome counters or the histogram.
- Phase 2 keeps the **same subscription live**: when the corpus is consumed the subscription continues to receive the
  events the writer appends at `rate` during measure; the open-loop rules and latency definition are those of the
  persistent subscription kind, with the catch-up subscription as the receiver. The corpus events are not counted in
  phase 2.

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
| `cpuUserSeconds`, `cpuSystemSeconds` | number | process CPU delta from the start of measure to the end of drain (`getrusage(RUSAGE_SELF)` or equivalent) |
| `maxRssBytes` | uint64 | process-lifetime peak resident set size, in bytes (not a delta) (`ru_maxrss` is KiB on Linux, bytes on macOS: normalise) |
| `ackEnqueued` | int? | persistent subscription: acks sent by the client; else absent/null |
| `uniqueDeliveries` | int? | subscription kinds: distinct events delivered; else null |
| `redeliveries` | int? | subscription kinds: deliveries of an already seen event; else null |
| `catchUpSeconds` | number? | catch-up: wall time of phase 1 until the last corpus event; else null |
| `validation` | object | see below |

Optional fields may be omitted or `null`.

### `validation`

`{ "expectedEvents": int, "receivedEvents": int, "payloadSizesOk": bool }`.

| `kind` | `expectedEvents` | `receivedEvents` | Class |
|---|---|---|---|
| `appendLatency`, `appendThroughput` | `succeeded * batchSize` | the same events confirmed by the driver's own bookkeeping | informational |
| `rebuild` | streams read by succeeded reads `* streamLength` | events decoded | **hard** (seeded count) |
| `persistentSubscription` | events the writer appended successfully | unique deliveries | reported |
| `catchUp` | phase 1: `catchUpExpectedEvents` (hard, seeded count; the trial fails if fewer arrive); live phase: events the writer appended successfully (reported). Report `expectedEvents` and `receivedEvents` as the sums over both phases | unique events received | mixed, see below |

`payloadSizesOk` is true iff every event the driver read or received had `eventSize` bytes of data and `metadataSize`
bytes of metadata (append kinds: true when the driver built payloads of those sizes).

How the orchestrator interprets it:

- **Hard failures** (the trial is marked failed): `payloadSizesOk == false`; and a mismatch of a **seeded** count:
  rebuild `receivedEvents != expectedEvents`, catch-up phase 1 not receiving all `catchUpExpectedEvents` (the driver
  waits for them up to a bounded time, exits 0 and reports `catchUpSeconds` null; the orchestrator fails a catch-up trial
  whose `catchUpSeconds` is null).
- **Reported, not failing**: for live-write kinds (persistent subscription, catch-up phase 2) `expectedEvents`
  (written) versus `receivedEvents` (unique deliveries) is a reported number. A shortfall is shown in the report and
  already shows up as timeouts in the outcome counts; it does not fail the trial.
- Append kinds are informational: the orchestrator records the pair but does not fail on it.

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
