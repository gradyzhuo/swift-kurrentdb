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
| `streamPrefix` | string | stream name prefix; equal to `category` and free of `-` (see below) |
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
(`ru_maxrss`, not a delta; includes warmup); a .NET driver must report its process peak too (`ru_maxrss`, or
`Process.PeakWorkingSet64`, which reads the same kernel peak on Linux), not a managed-heap figure.

### Warmup isolation

Warmup never touches measured data. Warmup streams are named `<streamPrefix>w-<n>` and the warmup category is
`<category>w` (that is, `streamPrefix + "w"` and `category + "w"`, then `-<n>` as usual). Warmup appends go only to
those streams; warmup reads (rebuild) use the same shape against `<streamPrefix>w-*` streams; warmup subscriptions
(persistent and catch-up) use the `$ce-<category>w` stream. The harness seeds whatever warmup data a kind needs before
`run`, exactly as for the measured data. For persistent subscriptions the harness also creates a second group,
`groupName + "w"`, on `$ce-<category>w`; the driver does not create groups (see below). Measured streams, the measured category and the measured
group are untouched until the measure window starts.

`$by_category` takes everything before the **first** `-` of a stream name as its category, so `<streamPrefix>-<n>` is
in `$ce-<category>` and `<streamPrefix>w-<n>` in `$ce-<category>w` only when `streamPrefix == category` and neither
contains `-`. Whoever writes the scenario (orchestrator, test harness) keeps them that way.

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
generator, restarted at `state = seed`, with the `w` names (rebuild warmup reads `<streamPrefix>w-<z % rebuildStreams.count>`,
so the harness seeds `<streamPrefix>w-0 ..< <streamPrefix>w-<rebuildStreams.count>` like the measured streams).
Draw *i* only depends on `seed` and *i*: it is the mix of `seed + (i + 1) * 0x9E3779B97F4A7C15`. Reference:
`Sources/LiveBenchCore/SeededDraw.swift`.

### Event bytes

Every appended event has:

- event type `BenchEvent`, content type `application/json` (data and metadata are both JSON);
- data of exactly `eventSize` bytes and metadata of exactly `metadataSize` bytes, built by the following function;
- event index `k = i * batchSize + j` for event `j` (0-based) of operation `i`.

`make(size, k, seed')` returns the ASCII bytes `{"i":<k>,"p":"` + `fillerCount` filler bytes + `"}`, where `<k>` is
decimal and `fillerCount = size - len(prefix) - len(suffix)` (prefix `{"i":<k>,"p":"`, suffix `"}`; size is always large
enough). The filler comes from a **pool of 1024 bodies** per payload kind, computed once before warmup:

- `width = size - len("{\"i\":0,\"p\":\"") - len("\"}") = size - 12 - 2 = size - 14` (the filler length of a one-digit index, the
  longest any index gets).
- Pool entry `j` (`0 <= j < 1024`) is `width` bytes over
  `alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"` (62 bytes):

```
state = seed' XOR (j * 0xBF58476D1CE4E5B9)            (mod 2^64)
repeat width times:
    state = state + 0x9E3779B97F4A7C15                (mod 2^64)
    z = state
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9          (mod 2^64)
    z = (z ^ (z >> 27)) * 0x94D049BB133111EB          (mod 2^64)
    z = z ^ (z >> 31)
    append alphabet[z % 62]
```

- Event `k` uses entry `k % 1024`, **truncated to its first `fillerCount` bytes** (an index with more digits gets a
  shorter filler, so every payload has exactly `size` bytes). Indices 1024 apart with the same number of digits share
  their filler and differ only in `"i"`.

Data uses `seed' = seed`; metadata uses `seed' = seed + 0x9E3779B97F4A7C15 (mod 2^64)`, each with its own pool. Reference:
`Sources/LiveBenchCore/Payload.swift` (`PayloadTests.poolEntryIsTheSeededGenerator` restates the rule independently).

Events are built **inline on the operation path** from the precomputed pools (a prefix, a slice and a suffix: two small
copies). There is no look-ahead producer: generation is cheap enough to be part of the client's operation, and the
same for every client.

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
| `rebuild` | read of one whole stream (picked from `rebuildStreams`, seeded) forward from the start, decoding every event (a full JSON DOM parse of the data: Swift `JSONSerialization.jsonObject`, .NET `JsonDocument.Parse`) | all `streamLength` events decoded |
| `persistentSubscription` | append of one event (stream picked per "Random choices") at `rate` events/s; latency = writer's `min(scheduled, launch)` to the subscriber's first receipt of that event | event received (first delivery) |
| `catchUp` | see "Catch-up" below | event received by the live phase |

For subscription kinds the writer is part of the driver (same process, same open-loop rules, expected revision any).
The append outcome is the operation outcome for accounting; the latency of a succeeded operation is taken at the
subscriber's receipt: origin is `min(scheduled instant of the append, actual launch of the append)` (rule 3), end is the
first receipt of that event (matched by the event's index `k`). An append that succeeds but whose event is never received
by `scheduled + deadline` is a timeout (rule 5). Receipts of an event already received count as `redeliveries`.
The operation therefore completes at the receipt, which may come before the append's response: the Swift driver
registers the event as awaited, starts the append, and completes the operation on the first receipt, or fails it if the
append throws first. A receipt is matched by parsing `k` from the data prefix `{"i":<k>,`.
**The end instant is the receipt instant, stamped on the receiving callback (the subscription's event loop body)
before any hand-off** to the operation's task or another thread; the time to wake the waiting operation is not part of
the latency. Deadline rules apply to that instant (a receipt at or after `scheduled + deadline` is a timeout). The Swift
reference is the `runOpenLoop` overload whose operation returns its completion instant.

### Persistent subscription

- The harness creates the group before `run` (resolve links on, RoundRobin, start from the beginning of
  `$ce-<category>`; name in `groupName`). The driver must not create, update or delete it.
- The driver connects `consumers` (absent = 1) consumers to the group in the same process, with default client
  options, and **acks each event on receipt** (one ack per event; `ackEnqueued` counts acks handed to the client).
- `uniqueDeliveries` counts distinct events across all consumers.
- Warmup runs the same way against group `groupName + "w"` on `$ce-<category>w`; its consumers are stopped before the
  measured group is first connected, right before the measure window.
- After the drain the measured consumers **stay connected for 3 s** (outside the CPU window) before they are closed:
  an ack still in transit when its connection closes is lost (the event goes back to be retried), and the server's
  acknowledged progress, which the orchestrator reads after the driver exits, would fall short. During the settle the
  consumers keep receiving and acking as before (a late delivery or redelivery is acked), but the delivery counters
  (`uniqueDeliveries`, `redeliveries`, `validation.receivedEvents`) are **snapshotted at the end of the drain, before
  the settle**; only `ackEnqueued` is read after it.

#### Group settings and acknowledged progress (orchestrator)

The orchestrator creates both groups per trial, identical for every client: name `g<round>-<rate>-<driver>` (warmup
twin `+ "w"`), `resolveLinkTos` on, RoundRobin, checkpoint after 1 to 1000 acked events (`checkpointAfter` default,
2 s), start from the beginning of the stream, every other setting default.

**Acknowledged progress observed by the server** (the headline throughput number of this kind) is
`SubscriptionInfo.lastCheckpointedEventPosition + 1` of the measured group (0 while the field is empty), read after
the driver exits, polling for up to 10 s until it reaches the events the writer appended. Finding of
`PersistentProgressLiveTests.checkpointAdvancesOnlyOnAck` (kurrentdb 26.2.3, 100 events delivered to one consumer):

| state | `totalItems` | `lastCheckpointedEventPosition` | `outstandingMessageCount` |
|---|---|---|---|
| all delivered, none acked, 5 s later | 100 | (empty) | 100 |
| all acked, `checkpointAfter` + 2 s later | 100 | `99` | 0 |
| consumer disconnected, 2 s later | 100 | `99` | 0 |

`totalItems` counts deliveries, not acks; `lastCheckpointedEventPosition` moves only on acks. It is the revision of the
last event of the **contiguous acked prefix** in the `$ce-` stream, so it counts events only because each trial's
`$ce-<category>` holds just that trial's events from revision 0. Caveats: it lags acks by up to `checkpointAfter`, an
event whose ack is lost holds it back until the event is retried and acked, and acks the server had not processed
when a consumer disconnected never count (closing a consumer right after its 20th ack left the checkpoint at 16 of 20,
hence the 3 s above). A shortfall against the events written is reported, not a failure.

### Catch-up

**Precondition:** at driver start `$ce-<category>` holds exactly `catchUpExpectedEvents` events (the orchestrator
guarantees it by restoring the seeded snapshot; when the corpus was reduced, `corpusReducedTo` is what the scenario
carries as `catchUpExpectedEvents`). The driver relies on it: the first `catchUpExpectedEvents` receipts are the corpus.

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
  phase 2: the first `catchUpExpectedEvents` events the subscription receives are the corpus, everything after them is
  matched to the writer. `uniqueDeliveries` and `redeliveries` cover phase 2 only.
- The bounded wait for phase 1 is `max(120 s, catchUpExpectedEvents / 1000 s)` (at least 1,000 events/s). If it
  expires, the driver skips phase 2 and writes a phase-1 shortfall result: all outcome counters 0, `measuredSeconds`
  0, `cpuUserSeconds` and `cpuSystemSeconds` 0, `catchUpSeconds: null`, an empty histogram, and validation
  `expectedEvents = catchUpExpectedEvents`, `receivedEvents` = corpus events received. Consumers must not divide by
  `measuredSeconds` or `scheduled` without checking for 0.

### ghz (transport reference)

ghz is not a driver of this contract: the orchestrator runs it for append and rebuild cells only, from the call
configs `drivers/ghz/append.json` and `read.json` (`proto/kurrentdb/v1/streams.proto` of this repository, `Streams.Append`
/ `Streams.Read`), and converts its JSON report (`GhzAdapter`) to the two output files with `timing: "rpcStart"`.
What it shares with the drivers: target rate, measure and warmup lengths (warmup as a separate ghz run on the `w`
streams), the per-call deadline (ghz `timeout`), `inFlightCap` as ghz `concurrency`, one connection, the stream set,
batch size, event type, content type, expected revision any, and exact data and metadata sizes. What differs:
latency from the RPC start; a full worker pool waits instead of dropping (no drops, wait not charged); streams in round
robin instead of the seeded draw; every event carries the bytes of event index 0; rebuild reads are not decoded and
counts are not checked; process CPU and RSS are not measured. Its numbers are never put in a ratio.

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
| `rebuild` | (succeeded reads + reads that completed with a count other than `streamLength`) `* streamLength` | `succeeded * streamLength` + events of those wrong-count reads (a wrong-count read is a failure, so any one makes the two differ). Events of a read that throws mid-stream are not counted (that read is a failure and neither side includes it) | **hard** (seeded count) |
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
- **Measure-start marker (mandatory):** at the instant the measure window starts (immediately before the open loop of
  the measured window; catch-up: the start of phase 2's measure window, after phase 1), the driver writes the exact
  line `LIVE_BENCH_MEASURE_START` to **stderr, unbuffered**, once per run. The orchestrator watches the driver's stderr,
  starts the headroom monitor on that line and stops it `measureSeconds` later (or when the driver exits, if earlier).
  If the marker never appears the trial's headroom is unavailable (null) and the trial carries a note saying so. A
  catch-up driver that ends with a phase-1 shortfall writes no marker. (ghz writes none; its measured run is a separate
  process whose launch starts the window.)
- stdout is free for logging; the orchestrator reads only the two files (and `version` stdout), the measure-start
  marker on stderr, plus the tail of stderr on failure. Logs go either to stderr (unbuffered) or to stdout flushed after each line, so the log of a killed driver is
  complete. The Swift driver writes each stdout line unbuffered.
- Do not write outside `--out`.

## .NET notes

The .NET driver (`drivers/dotnet`, `KurrentDB.Client` pinned exactly in `LiveDriver.DotNet.csproj` and
`packages.lock.json`, .NET 8) follows every rule above. Build it (locally and in CI) with
`dotnet build Benchmarks/Live/drivers/dotnet -c Release -p:RestoreLockedMode=true`, so a restore that would drift from
the lock file fails. `version` reports the informational version of the `KurrentDB.Client` assembly actually loaded
(build metadata stripped). Where the .NET client's API or runtime shapes the mapping, it
does this:

- **Clients.** `KurrentDBClientSettings.Create(<connection string>)` with nothing changed. Streams go through
  `KurrentDBClient`; persistent subscriptions need the separate `KurrentDBPersistentSubscriptionsClient` built from the
  same settings, so a persistent-subscription trial has two gRPC channels (the Swift driver uses one client).
- **Persistent subscription consumers.** `SubscribeToStream(stream, group)` with the client's default `bufferSize` of
  **10** (the Swift SDK's default is 1000). Both are client defaults and stay as they are in headline runs; the buffer
  bounds the unacked events the server sends one consumer. Each event is acked on receipt with one `Ack(resolvedEvent)`
  call (no batching), and `ackEnqueued` counts completed `Ack` calls. The driver waits for each consumer's
  `SubscriptionConfirmation` before the window starts. Link resolution is the group's setting (created by the harness).
- **Catch-up.** `SubscribeToStream($ce-<category>, FromStream.Start, resolveLinkTos: true)`, read through `Messages`;
  only `StreamMessage.Event` messages count as receipts. The .NET subscription starts lazily, so the driver waits for
  its `SubscriptionConfirmation` (60 s bound): a subscription that fails before it makes the driver exit 1 at once, as
  the Swift SDK's `subscribe()` throws, instead of waiting out the phase-1 limit.
- **Rebuild.** `ReadStreamAsync(Forwards, stream, Start)` with defaults; each event's data goes through
  `JsonDocument.Parse`. A read of a stream that does not exist is a failure (the Swift SDK throws), not a short read.
- **Scheduler.** A dedicated thread sleeps with `nanosleep(2)` (nanosecond resolution, no millisecond rounding as in
  `Thread.Sleep` / `Task.Delay`) and applies the same overshoot estimate as the Swift waker (EWMA 1/16, capped at 1 ms,
  no spinning). Each launch is queued to the thread pool (`ThreadPool.UnsafeQueueUserWorkItem`), as the Swift driver
  starts a `Task`. The deadline timer is `CancellationTokenSource.CancelAfter` (a millisecond timer, armed with the span
  rounded up plus 1 ms so it never fires before `scheduled + deadline`; the drain wait loops the same way until the
  drain end has passed): it decides when a still-outstanding operation is recorded as a timeout and leaves the cap; a
  completion is judged against the deadline by its own instant, as in rule 5. An operation that throws after its token
  was cancelled (deadline or drain end) is a timeout, never a failure, even when its exception reaches the ledger
  before the timeout callback does (.NET runs cancellation callbacks in reverse registration order).
- **Parity test.** `dotnet LiveDriver.DotNet.dll selftest --mode ...` runs the open loop with synthetic operations
  (no-op, throw, stall past the deadline with and without honouring cancellation, inline cancellation, a completion
  instant past the deadline, over the cap with drain expiry); `OpenLoopParityTests` runs the same cases through
  `runOpenLoop` and requires identical counters.
- **Process figures.** CPU and peak RSS come from `getrusage(RUSAGE_SELF)` (P/Invoke), the Swift driver's source;
  on Linux `ru_maxrss` is the kernel's VmHWM, which `Process.PeakWorkingSet64` also reports.
- **Runtime defaults.** No GC, thread-pool or tiered-compilation settings are changed. The .NET thread pool's workers
  spin briefly before sleeping (`ThreadPool_UnfairSemaphoreSpinLimit` default), which keeps wake-ups short but costs
  process CPU even with a no-op operation: about 0.2 cores at 1000/s and 1.3 cores at 8000/s on an Apple Silicon Mac
  (about 0.03 and 0.12 cores with the spin limit set to 0). That CPU is part of a default .NET process and is counted in
  `cpuUserSeconds`/`cpuSystemSeconds`; read the CPU ratios with it in mind.
- **Harness floor** (rule 10): `dotnet LiveDriver.DotNet.dll floor --rate <r> [--seconds <s>] [--warmup <s>]` runs the
  same scheduler with a no-op operation after a warmup window and prints p50/p99. Release build, Apple Silicon Mac,
  5 s after a 2 s warmup, p50 / p99: 1000/s 5-7 / 111-153 µs, 8000/s 5-6 / 73-138 µs (Swift on the same machine,
  `OpenLoopTests.noOpCalibrationFloor` in release: 1000/s 7 / 241-282 µs, 8000/s 3-6 / 31-88 µs). Without warmup
  (0.5 s windows, JIT still tiering) the .NET p99 is sometimes several ms, which is why the floor is taken after a
  warmup, as every trial has one. In a Linux container on the same Mac (Docker Desktop VM, not CI-representative) both
  harnesses are much noisier and similar: .NET 1000/s 204 / 2945 µs, 8000/s 281 / 3521 µs; Swift 1000/s 220-443 /
  2579-2829 µs, 8000/s 460-521 / 4083-16559 µs.
