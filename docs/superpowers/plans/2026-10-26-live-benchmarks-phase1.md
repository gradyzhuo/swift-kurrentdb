# Live Benchmarks Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Benchmark the Swift SDK against `KurrentDB.Client` (.NET) and ghz on a real KurrentDB 26.2 server inside GitHub Actions: an on-demand comparison workflow that publishes a report, and a nightly Swift-only trend job that uploads to Bencher.

**Architecture:** A standalone SwiftPM package at `Benchmarks/Live` holds a pure-logic core library (scheduling, accounting, statistics, result formats), the Swift driver and the orchestrator. A .NET console driver and a ghz adapter implement the same driver contract. The orchestrator runs one *cell* (scenario × event size) per GitHub job: it controls the server container, seeds data, runs every trial from a restored snapshot, interleaves clients over rounds, monitors server headroom, and renders a self-contained HTML report.

**Tech Stack:** Swift 6 (swift-tools 6.0), Swift Testing, `KurrentDB` (repo root by path), `hdrhistogram-swift` 0.1.4, swift-argument-parser; .NET 8 + `KurrentDB.Client` + `HdrHistogram` NuGet; ghz v0.120.0; Docker; GitHub Actions; Bencher CLI.

**Spec:** `docs/superpowers/specs/2026-10-25-live-benchmarks-design.md` (approved 2026-10-26). Read it before any task; this plan only adds the decisions the spec leaves open.

## Global Constraints

- Root `Package.swift` is not modified. `Benchmarks/Live` is its own package (`name: "LiveBenchmarks"`), depending on the root via `.package(path: "../..")` and `.product(name: "KurrentDB", package: "swift-kurrentdb")`.
- Platforms in `Benchmarks/Live/Package.swift`: `.macOS(.v15)`; Linux is the CI target.
- No hostname, IP, username or internal topology of any private machine anywhere in the repo, workflows, results or reports. The metadata collector never records `hostname`.
- Code comments, docs, report text and commit messages in English. Commit format `[TAG] English summary` (`[ADD]`, `[UPDATE]`, `[FIX]`), files added one by one (`git add <file>`), never commit on `main`, end every message with the attribution lines from the session.
- No CI-failing latency thresholds from the live suite.
- Headline runs use each SDK's default client settings.
- Server image: `kurrentplatform/kurrentdb:26.2.<patch>`, exact tag pinned in `Benchmarks/Live/config/server.json`, digest recorded per run.
- Tests use Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`). Tests that need Docker are gated by env `LIVE_BENCH_DOCKER=1` via `.enabled(if:)`.
- All latencies are recorded in microseconds (`UInt64`).

### Fixed initial parameters (from the spec, plus values the spec leaves to the builder)

These live in `Benchmarks/Live/config/` and are fixed before the first published run.

| Name | Value |
|---|---|
| Event sizes | 300, 1024, 4096 bytes of JSON data; metadata 60 bytes |
| Append streams | 100,000, uniform random |
| Append batch | 1 (latency), 50 (throughput) |
| Rebuild lengths | 10, 100, 1,000, 10,000 events × 100 streams each |
| Catch-up corpus | 1,000,000 events in one category |
| Warmup / measure / drain | 30 s / 60 s / 5 s |
| Per-operation deadline | 5 s |
| In-flight cap | 256, identical for every client |
| Sustained | successful rate ≥ 0.99 × target, (errors+drops+timeouts)/scheduled ≤ 0.001, backlog not growing |
| Headroom gate | each server core mean busy ≤ 85%; disk await ≤ 20 ms; disk queue depth ≤ 4; `$by_category` `bufferedEvents` at end ≤ at start + 1% of events written |
| Rounds | ≥ 5 headline, ≥ 3 appendix |
| Confidence | 95%, Student t over round-level log-ratios |
| Target ratio | 1.2 |
| Headline rates (append latency, ops/s) | 250, 500, 1000, 2000, 4000, 8000 |
| Headline rates (append throughput, batches/s) | 20, 50, 100, 200, 400 |
| Rebuild rates (whole-stream reads/s) | L10: 100, 500, 2000 · L100: 50, 200, 800 · L1000: 5, 20, 80 · L10000: 1, 2, 8 |
| Persistent subscription (events/s) | 250, 1000, 4000 |
| Catch-up live phase (events/s) | 250, 1000 |
| Appendix rates | the 2nd and 4th headline rate of the same scenario (2nd and 3rd where only 3 exist) |

Rebuild is one cell per length (four cells), so each cell fits a 6-hour job. The orchestrator refuses a cell whose estimated duration exceeds 330 minutes.

### Planning calls (deviations from the spec's wording, for the maintainer to check)

- Scenario and cell files are **JSON**, not YAML: drivers in two languages read them with their standard library and no YAML dependency.
- The driver's "HdrHistogram file" is a JSON bucket list (format in Task 2), which both languages can write and the orchestrator merges.
- If the catch-up corpus does not fit the disk budget for a 4 KB cell, the orchestrator reduces it to fit and records `corpusReducedTo` in the metadata; the report states it.

## Review Focus

1. **A driver crashes or exits non-zero mid-trial** → the orchestrator records that trial as failed with the exit status and stderr tail, does not hang, and continues with the next client. Test in Task 9.
2. **The server never becomes ready, or its container dies mid-cell** → bounded wait (120 s), the cell ends with a recorded reason, no partial ratios published. Test in Task 7.
3. **A step where every operation fails (zero successes)** → no NaN or division by zero anywhere; percentiles all "> deadline"; the step is "not sustained". Tests in Tasks 2 and 4.
4. **A round where only one client produced data** → that round is excluded from paired ratios (never paired across rounds); CI is computed from the remaining rounds and the cell is flagged if it falls below the minimum. Test in Task 4.
5. **Private host details leaking into results** → the metadata and report contain no `hostname`, no private IPs, no usernames. Test in Task 10.

---

### Task 1: Package skeleton, scenario model and payloads

**Files:**
- Create: `Benchmarks/Live/Package.swift`
- Create: `Benchmarks/Live/Sources/LiveBenchCore/Scenario.swift`
- Create: `Benchmarks/Live/Sources/LiveBenchCore/Payload.swift`
- Create: `Benchmarks/Live/config/cells.json`, `Benchmarks/Live/config/server.json`
- Modify: `.gitignore` (add `!Benchmarks/Live/Package.resolved`)
- Test: `Benchmarks/Live/Tests/LiveBenchCoreTests/ScenarioTests.swift`, `PayloadTests.swift`

**Interfaces:**
- Produces:
  - Targets: `LiveBenchCore` (library, no KurrentDB dependency), `LiveDriverSwift` (executable, path `drivers/swift`), `LiveOrchestrator` (executable, path `orchestrator`), test targets `LiveBenchCoreTests`, `LiveOrchestratorTests`.
  - `enum ScenarioKind: String, Codable, Sendable, CaseIterable { case appendLatency, appendThroughput, rebuild, persistentSubscription, catchUp }`
  - Test fixtures `Cell.fixture(kind:eventSize:streamLength:tier:)` and `EffectiveScenario.fixture(kind:rate:measureSeconds:)` in `Tests/LiveBenchCoreTests/Support/Fixtures.swift`, shared with `LiveOrchestratorTests` (symlink or duplicated file — implementer's choice).
  - `enum Tier: String, Codable, Sendable { case headline, appendix }`
  - `struct Cell: Codable, Sendable, Identifiable { id: String; kind: ScenarioKind; eventSize: Int; tls: Bool; streamLength: Int?; tier: Tier; rates: [Double]; rounds: Int }`
  - `struct EffectiveScenario: Codable, Sendable` — what a driver receives: `cellId, kind, eventSize, metadataSize, batchSize, streamCount, streamPrefix, category, groupName?, streamLength?, rebuildStreams: [String]?, catchUpExpectedEvents: Int?, rate, warmupSeconds, measureSeconds, drainSeconds, deadlineMillis, inFlightCap, seed: UInt64`
  - `func loadCells(from url: URL) throws -> [Cell]`
  - `struct PayloadFactory { init(dataSize: Int, metadataSize: Int, seed: UInt64); func data(index: Int) -> Data; func metadata(index: Int) -> Data }`

- [ ] **Step 1: Write failing tests**

```swift
@Test func cellsFileDecodes() throws {
    let cells = try loadCells(from: configURL("cells.json"))
    #expect(cells.contains { $0.id == "append-latency-300-tls" && $0.tier == .headline && $0.rounds >= 5 })
    #expect(cells.filter { $0.kind == .rebuild && $0.tier == .headline }.map(\.streamLength).sorted() == [10, 100, 1000, 10000])
    #expect(cells.allSatisfy { $0.tier == .headline ? $0.rounds >= 5 : $0.rounds >= 3 })
}
@Test(arguments: [300, 1024, 4096]) func payloadHasExactSizeAndIsJSON(size: Int) throws {
    let f = PayloadFactory(dataSize: size, metadataSize: 60, seed: 42)
    #expect(f.data(index: 7).count == size)
    #expect(f.metadata(index: 7).count == 60)
    _ = try JSONSerialization.jsonObject(with: f.data(index: 7))
}
@Test func payloadIsDeterministic() {
    #expect(PayloadFactory(dataSize: 300, metadataSize: 60, seed: 1).data(index: 3)
         == PayloadFactory(dataSize: 300, metadataSize: 60, seed: 1).data(index: 3))
}
```

- [ ] **Step 2: Run** `swift test --package-path Benchmarks/Live --filter LiveBenchCoreTests` — expect compile failure.
- [ ] **Step 3: Implement.** `cells.json` lists every cell of spec table "Splitting the comparison run" with the rates above (cell id pattern `<kind>-<size>-<tls|notls>[-L<length>]`). `server.json`: `{ "image": "kurrentplatform/kurrentdb:26.2.<patch>" }`. Payload: a JSON object `{"i":<index>,"p":"<filler>"}` padded with seeded ASCII filler to the exact byte count.
- [ ] **Step 4: Run tests** — PASS. Also `swift build --package-path Benchmarks/Live` succeeds.
- [ ] **Step 5: Commit** `[ADD] live benchmark package skeleton with cells, scenario model and sized payloads`

### Task 2: Outcome accounting, latency histograms and censored percentiles

**Files:**
- Create: `Benchmarks/Live/Sources/LiveBenchCore/Outcomes.swift`, `HistogramFile.swift`
- Test: `Benchmarks/Live/Tests/LiveBenchCoreTests/OutcomesTests.swift`

**Interfaces:**
- Produces:
  - `enum Outcome: Sendable { case success(latencyMicros: UInt64), failure, drop, timeout }`
  - `struct OutcomeRecorder: Sendable { mutating func record(_: Outcome); var scheduled: Int; var succeeded: Int; var failed: Int; var dropped: Int; var timedOut: Int; var histogram: Histogram<UInt64> }` (latency histogram 1 µs … 60 s, 3 significant digits)
  - `enum PercentileValue: Codable, Equatable, Sendable { case micros(UInt64), censored }` — rendered as "> deadline"
  - `func percentile(_ p: Double, of r: OutcomeRecorder) -> PercentileValue` — rank over **all** scheduled attempts; losses rank as +∞
  - `struct HistogramFile: Codable { unit: String = "us"; buckets: [[UInt64]] }` — each bucket `[valueMicros, count]`; `init(_: Histogram<UInt64>)`, `func histogram() -> Histogram<UInt64>`

- [ ] **Step 1: Write failing tests**

```swift
@Test func censoredWhenRankFallsInLosses() {
    var r = OutcomeRecorder()
    for i in 0..<9_995 { r.record(.success(latencyMicros: UInt64(1_000 + i))) }
    for _ in 0..<3 { r.record(.timeout) }; for _ in 0..<2 { r.record(.drop) }
    #expect(r.scheduled == 10_000)
    #expect(percentile(99.9, of: r) != .censored)
    #expect(percentile(99.99, of: r) == .censored)
}
@Test func allFailedStepHasNoNumbers() {
    var r = OutcomeRecorder(); for _ in 0..<100 { r.record(.failure) }
    #expect(percentile(50, of: r) == .censored)
    #expect(r.succeeded == 0)
}
@Test func histogramFileRoundTrips() throws {
    var r = OutcomeRecorder(); [5, 50, 500, 5_000].forEach { r.record(.success(latencyMicros: $0)) }
    let back = try JSONDecoder().decode(HistogramFile.self, from: JSONEncoder().encode(HistogramFile(r.histogram))).histogram()
    #expect(back.totalCount == 4)
    #expect(back.valueAtPercentile(100) == r.histogram.valueAtPercentile(100))
}
```

- [ ] **Step 2: Run** — FAIL (undefined types).
- [ ] **Step 3: Implement.** `percentile`: rank = ceil(p/100 × scheduled); if rank > succeeded → `.censored`, else the histogram value at percentile `rank / succeeded × 100`. Buckets come from iterating recorded values.
- [ ] **Step 4: Run** — PASS.
- [ ] **Step 5: Commit** `[ADD] outcome accounting with percentiles ranked over all scheduled attempts`

### Task 3: Open-loop scheduler with in-flight cap, deadline and drain

**Files:**
- Create: `Benchmarks/Live/Sources/LiveBenchCore/OpenLoop.swift`
- Test: `Benchmarks/Live/Tests/LiveBenchCoreTests/OpenLoopTests.swift`

**Interfaces:**
- Consumes: `OutcomeRecorder`, `Outcome` (Task 2)
- Produces:
  - `struct OpenLoopConfig: Sendable { rate: Double; duration: Duration; inFlightCap: Int; deadline: Duration; drain: Duration }`
  - `func runOpenLoop(_ config: OpenLoopConfig, clock: some Clock<Duration> = ContinuousClock(), operation: @escaping @Sendable (_ index: Int) async throws -> Void) async -> OutcomeRecorder`
  - Semantics: operation *i* is scheduled at `start + i/rate`. Latency = completion − **scheduled** time. If in-flight ≥ cap at the scheduled instant → `.drop`. An operation exceeding `deadline` → `.timeout` (its task is cancelled). At the end of `duration` nothing new is scheduled; after `drain`, still-running operations → `.timeout`. Thrown errors → `.failure`.

- [ ] **Step 1: Write failing tests** (use a small rate and short durations; a `TestClock` is optional — real `ContinuousClock` with 50–200 ms windows is acceptable)

```swift
@Test func stalledOperationDelaysAreMeasuredFromSchedule() async {
    // 100 ops/s for 0.5 s; op #2 stalls 200 ms. Later ops must still be scheduled on time.
    let r = await runOpenLoop(.init(rate: 100, duration: .milliseconds(500), inFlightCap: 256, deadline: .seconds(1), drain: .milliseconds(300))) { i in
        if i == 2 { try await Task.sleep(for: .milliseconds(200)) }
    }
    #expect(r.scheduled == 50)
    #expect(r.histogram.valueAtPercentile(100) >= 200_000)
}
@Test func capProducesDropsNotBackpressure() async {
    let r = await runOpenLoop(.init(rate: 200, duration: .milliseconds(200), inFlightCap: 2, deadline: .seconds(2), drain: .seconds(1))) { _ in
        try await Task.sleep(for: .milliseconds(100))
    }
    #expect(r.dropped > 0); #expect(r.scheduled == 40)
}
@Test func unfinishedAfterDrainCountAsTimeouts() async {
    let r = await runOpenLoop(.init(rate: 10, duration: .milliseconds(100), inFlightCap: 10, deadline: .seconds(10), drain: .milliseconds(50))) { _ in
        try await Task.sleep(for: .seconds(5))
    }
    #expect(r.timedOut == r.scheduled)
}
@Test func throwingOperationIsAFailure() async {
    struct E: Error {}
    let r = await runOpenLoop(.init(rate: 50, duration: .milliseconds(100), inFlightCap: 10, deadline: .seconds(1), drain: .milliseconds(100))) { _ in throw E() }
    #expect(r.failed == r.scheduled)
}
```

- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement** with a `TaskGroup`; the scheduling loop sleeps until each scheduled instant (`clock.sleep(until:)`), never waits for completions.
- [ ] **Step 4: Run** — PASS (run 3 times to check for flakiness).
- [ ] **Step 5: Commit** `[ADD] open-loop scheduler that measures from scheduled time and caps in-flight work`

### Task 4: Step evaluation and statistics

**Files:**
- Create: `Benchmarks/Live/Sources/LiveBenchCore/Evaluation.swift`, `Statistics.swift`
- Test: `Benchmarks/Live/Tests/LiveBenchCoreTests/EvaluationTests.swift`, `StatisticsTests.swift`

**Interfaces:**
- Consumes: `OutcomeRecorder` (Task 2)
- Produces:
  - `func isSustained(_ r: OutcomeRecorder, targetRate: Double, measuredSeconds: Double, backlogGrew: Bool) -> Bool`
  - `struct HeadroomSample: Codable, Sendable { coreBusy: [Double]; diskAwaitMillis: Double; diskQueueDepth: Double; projectionBufferedStart: Int64; projectionBufferedEnd: Int64; eventsWritten: Int64 }`
  - `func hasHeadroom(_ s: HeadroomSample) -> Bool`
  - `enum Direction { case lowerIsBetter, higherIsBetter }`
  - `struct RoundPair: Sendable { swift: Double?; dotnet: Double? }`
  - `struct RatioEstimate: Codable, Sendable { point: Double; lower: Double; upper: Double; rounds: Int }`
  - `enum Verdict: String, Codable { case meets, misses, inconclusive, insufficientRounds }`
  - `func estimateRatio(_ pairs: [RoundPair], direction: Direction, minimumRounds: Int) -> (RatioEstimate?, Verdict)` — ratio oriented so higher = Swift worse; pairs with a missing side are dropped; 95% CI from Student t over log-ratios; verdict vs 1.2

- [ ] **Step 1: Write failing tests**

```swift
@Test func throughputHalfSpeedMisses() {
    let pairs = (0..<5).map { _ in RoundPair(swift: 500, dotnet: 1000) }
    let (e, v) = estimateRatio(pairs, direction: .higherIsBetter, minimumRounds: 5)
    #expect(abs(e!.point - 2.0) < 1e-9); #expect(v == .misses)
}
@Test func intervalStraddlingTargetIsInconclusive() {
    let ratios = [0.98, 1.05, 1.14, 1.25, 1.33]
    let pairs = ratios.map { RoundPair(swift: $0, dotnet: 1) }
    #expect(estimateRatio(pairs, direction: .lowerIsBetter, minimumRounds: 5).1 == .inconclusive)
}
@Test func tightIntervalBelowTargetMeets() {
    let pairs = [1.05, 1.07, 1.08, 1.09, 1.10].map { RoundPair(swift: $0, dotnet: 1) }
    #expect(estimateRatio(pairs, direction: .lowerIsBetter, minimumRounds: 5).1 == .meets)
}
@Test func unpairedRoundsAreDroppedNotMixed() {
    let pairs = [RoundPair(swift: 1.1, dotnet: 1), RoundPair(swift: nil, dotnet: 1), RoundPair(swift: 1.0, dotnet: nil)]
        + Array(repeating: RoundPair(swift: 1.1, dotnet: 1), count: 3)
    let (e, v) = estimateRatio(pairs, direction: .lowerIsBetter, minimumRounds: 5)
    #expect(e?.rounds == 4); #expect(v == .insufficientRounds)
}
@Test func zeroSuccessStepIsNotSustainedAndHasNoNaN() {
    var r = OutcomeRecorder(); for _ in 0..<10 { r.record(.failure) }
    #expect(!isSustained(r, targetRate: 10, measuredSeconds: 1, backlogGrew: false))
}
@Test func singleSaturatedCoreFailsHeadroom() {
    #expect(!hasHeadroom(.init(coreBusy: [0.95, 0.30], diskAwaitMillis: 1, diskQueueDepth: 0.2, projectionBufferedStart: 0, projectionBufferedEnd: 0, eventsWritten: 1000)))
}
```

- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement** with the thresholds in "Fixed initial parameters" as named constants in `Evaluation.swift`. Student t critical values: a lookup table for df 1…30, normal 1.96 beyond. Any non-finite intermediate → `insufficientRounds`.
- [ ] **Step 4: Run** — PASS.
- [ ] **Step 5: Commit** `[ADD] sustained and headroom gates, and paired log-ratio estimates oriented so higher means Swift is worse`

### Task 5: Driver contract (CLI, result file, process usage)

**Files:**
- Create: `Benchmarks/Live/Sources/LiveBenchCore/DriverContract.swift`, `ProcessUsage.swift`
- Create: `Benchmarks/Live/docs/driver-contract.md`
- Test: `Benchmarks/Live/Tests/LiveBenchCoreTests/DriverContractTests.swift`

**Interfaces:**
- Consumes: `EffectiveScenario` (Task 1), `OutcomeRecorder`, `HistogramFile` (Task 2)
- Produces:
  - CLI every driver implements: `<driver> run --scenario <effective.json> --connection <connection string> --out <dir>` and `<driver> version` (prints `DriverVersion` JSON).
  - Output files in `<dir>`: `result.json` (`TrialResult`) and `histogram.json` (`HistogramFile`).
  - `struct TrialResult: Codable, Sendable { client: String; cellId: String; targetRate: Double; timing: Timing /* .scheduled | .rpcStart */; scheduled, succeeded, failed, dropped, timedOut: Int; measuredSeconds: Double; cpuUserSeconds, cpuSystemSeconds: Double; maxRssBytes: UInt64; ackEnqueued: Int?; uniqueDeliveries: Int?; redeliveries: Int?; catchUpSeconds: Double?; validation: Validation /* expectedEvents, receivedEvents, payloadSizesOk */ }`
  - `struct DriverVersion: Codable { client: String; clientVersion: String; runtime: String }`
  - `enum ProcessUsage { static func current() -> (user: Double, system: Double, maxRss: UInt64) }` (getrusage; `ru_maxrss` is KiB on Linux, bytes on macOS — normalise to bytes)
- `docs/driver-contract.md` states all of the above, the JSON field names, and that latency is measured from scheduled time.

- [ ] **Step 1: Write failing tests**

```swift
@Test func trialResultJSONFieldNamesAreStable() throws {
    let json = try String(data: JSONEncoder().encode(TrialResult.fixture), encoding: .utf8)!
    for key in ["\"client\"", "\"cellId\"", "\"timing\"", "\"scheduled\"", "\"timedOut\"", "\"maxRssBytes\"", "\"validation\""] {
        #expect(json.contains(key))
    }
}
@Test func processUsageIsPositive() { #expect(ProcessUsage.current().maxRss > 1_000_000) }
```

- [ ] **Step 2: Run** — FAIL. **Step 3: Implement.** **Step 4: Run** — PASS.
- [ ] **Step 5: Commit** `[ADD] driver contract: CLI, result and histogram files, process usage`

### Task 6: Swift driver — all five scenario kinds

**Files:**
- Create: `Benchmarks/Live/drivers/swift/main.swift`, `Append.swift`, `Rebuild.swift`, `Subscriptions.swift`
- Test: `Benchmarks/Live/Tests/LiveOrchestratorTests/SwiftDriverLiveTests.swift` (Docker-gated)

**Interfaces:**
- Consumes: Tasks 1–5; SDK: `ClientSettings.parse(connectionString:)`, `KurrentDBClient(settings:)`, `streams(specified:).append(events:)`, `read(configure:).lazy`, `streams(specified:).subscribe { $0.revision = .start; $0.resolveLinksEnabled = true }`, `persistentSubscriptions(stream:group:).subscribe()`, `Subscription.ack(readEvents:)`, `EventData(eventType:data:customMetadata:)`.
- Produces: executable `LiveDriverSwift` implementing the contract.
- Produces (test support, `Tests/LiveOrchestratorTests/Support/DriverHarness.swift`): `let docker: Bool` (env `LIVE_BENCH_DOCKER == "1"`), `enum Client { case swift, dotnet }`, `func runDriver(_ client: Client, scenario: EffectiveScenario) async throws -> TrialResult` (writes the scenario JSON, runs the built driver against a throwaway insecure container, decodes `result.json`).
- Behaviour per kind (operation = one open-loop index):
  - `appendLatency` / `appendThroughput`: append `batchSize` events to `"\(streamPrefix)-\(random 0..<streamCount)"`, default options.
  - `rebuild`: read one stream from `rebuildStreams` (uniform random) to the end with `.lazy`, JSON-decode every `record.data` (`JSONSerialization`), count events; validation checks count == `streamLength` and every size == `eventSize`.
  - `persistentSubscription`: one process runs a writer (open loop, appends to streams in `category`) and a consumer on the orchestrator-created group `groupName` on `$ce-<category>`. The writer stores scheduled time by event id; the consumer records delivery latency against it, acks each event, counts `ackEnqueued`, `uniqueDeliveries`, `redeliveries` (event id seen before). Default subscribe options.
  - `catchUp`: phase 1 subscribes to `$ce-<category>` from start with link resolution on, times receiving `catchUpExpectedEvents` → `catchUpSeconds`; phase 2 runs an open-loop writer into the same category and measures append-to-delivery latency like above.
  - Warmup uses `streamPrefix + "w"` / category `+ "w"` so it never touches measured data.

- [ ] **Step 1: Write failing live tests** (start a throwaway insecure 26.2 container in the test via `docker run`, or reuse Task 7's `ServerControl` once it exists — order: write these tests now against a container started by a small helper in the test file)

```swift
@Test(.enabled(if: ProcessInfo.processInfo.environment["LIVE_BENCH_DOCKER"] == "1"))
func appendLatencyAtLowRateProducesSustainedResult() async throws {
    let result = try await runDriver(.swift, scenario: .fixture(kind: .appendLatency, rate: 50, measureSeconds: 3))
    #expect(result.timing == .scheduled)
    #expect(result.succeeded == result.scheduled && result.scheduled == 150)
}
@Test(.enabled(if: ProcessInfo.processInfo.environment["LIVE_BENCH_DOCKER"] == "1"))
func rebuildValidatesCountsAndSizes() async throws { /* seed 3 streams × 10 events of 300 B, run, expect validation.receivedEvents == expectedEvents && payloadSizesOk */ }
@Test(.enabled(if: ProcessInfo.processInfo.environment["LIVE_BENCH_DOCKER"] == "1"))
func catchUpResolvesLinksSoPayloadSizesMatch() async throws { /* seed 1,000 events of 1 KB; expect payloadSizesOk (fails if links are not resolved) */ }
```

- [ ] **Step 2: Run** `LIVE_BENCH_DOCKER=1 swift test --package-path Benchmarks/Live --filter SwiftDriverLiveTests` — FAIL.
- [ ] **Step 3: Implement** the driver.
- [ ] **Step 4: Run** — PASS.
- [ ] **Step 5: Commit** `[ADD] Swift driver for append, rebuild, persistent and catch-up subscription scenarios`

### Task 7: Server control, certificates, snapshot restore and seeding

**Files:**
- Create: `Benchmarks/Live/orchestrator/ServerControl.swift`, `Seeder.swift`, `Shell.swift`
- Test: `Benchmarks/Live/Tests/LiveOrchestratorTests/ServerControlLiveTests.swift` (Docker-gated)

**Interfaces:**
- Produces:
  - `enum SecurityMode: String, Codable { case tlsAuth, plainAuth }` — `plainAuth` disables TLS but keeps authentication; never `KURRENTDB_INSECURE=true`. The implementer confirms the 26.2 settings (`DisableTls` + `ClusterSecret` per the spec) against the 26.2 docs.
  - `struct ServerControl { init(image: String, mode: SecurityMode, cpuset: String = "0,1", workDir: URL); func generateCertificates() throws; func start() async throws; func waitReady(timeout: Duration = .seconds(120)) async throws; func stop() throws; func snapshot() throws; func restoreSnapshot() throws; func dropCaches() throws; var connectionString: String; func imageDigest() throws -> String }`
  - `struct Seeder { func seed(cell: Cell, client: KurrentDBClient) async throws -> SeedManifest }` — rebuild streams, catch-up corpus; enables `projections(system: .byCategory)`; returns `SeedManifest { rebuildStreams: [String]; catchUpCategory: String?; catchUpEvents: Int; lastCommitPosition: UInt64; corpusReducedTo: Int? }`
  - `func waitForByCategory(client: KurrentDBClient, toReach position: UInt64, timeout: Duration) async throws` — polls `projections(system: .byCategory).detail()` `position`
- Certificates via `eventstore/es-gencert-cli:1.0.2` as in `server/docker-compose.yaml`; data directory on a host bind mount so `snapshot()`/`restoreSnapshot()` are `cp -a` of a stopped server's data; `dropCaches()` runs `sync; echo 3 | sudo tee /proc/sys/vm/drop_caches` (no-op with a warning on macOS).

- [ ] **Step 1: Write failing live tests**

```swift
@Test(.enabled(if: docker)) func plainAuthKeepsAuthenticationOn() async throws {
    let s = try await startedServer(.plainAuth)
    await #expect(throws: KurrentError.self) { try await anonymousClient(s).streams(specified: "x").append(events: [.fixture]) }
}
@Test(.enabled(if: docker)) func restoreBringsBackSeededStateExactly() async throws {
    // seed 10 events, snapshot, append 5 more, restore → stream has 10 events again
}
@Test(.enabled(if: docker)) func notReadyServerFailsWithinTimeout() async throws {
    // start with an invalid option so the container exits; waitReady(timeout: 10 s) throws ServerError.notReady within ~10 s
}
```

- [ ] **Step 2: Run** — FAIL. **Step 3: Implement.** **Step 4: Run** — PASS.
- [ ] **Step 5: Commit** `[ADD] server control with pinned cores, TLS or plain-with-auth modes, snapshot restore and seeding`

### Task 8: Headroom monitor and resource budget

**Files:**
- Create: `Benchmarks/Live/orchestrator/Monitor.swift`, `Budget.swift`
- Test: `Benchmarks/Live/Tests/LiveOrchestratorTests/MonitorTests.swift`, `BudgetTests.swift`

**Interfaces:**
- Consumes: `HeadroomSample` (Task 4)
- Produces:
  - `struct ProcStat { static func parse(_ text: String) -> [Int: (busy: UInt64, total: UInt64)] }` (per `cpuN` line of `/proc/stat`)
  - `struct DiskStats { static func parse(_ text: String, device: String) -> (ios: UInt64, ticksMillis: UInt64, weightedMillis: UInt64)? }` (`/proc/diskstats` fields 4/7/8/11/14)
  - `actor Monitor { init(cores: [Int], device: String, client: KurrentDBClient); func start(); func stop() async -> HeadroomSample }` (1 s sampling; core busy = Δbusy/Δtotal per core; await = Δ(read+write ticks)/Δios; queue = Δweighted/Δwall)
  - `struct Budget { static func estimatedMinutes(_ cell: Cell, clients: Int) -> Double; static func seedBytes(_ cell: Cell) -> Int64; static func check(freeBytes: Int64, cell: Cell) -> BudgetDecision /* .ok | .reduceCorpus(to: Int) | .refuse(reason: String) */ }` (per trial: 20 s restore/start + warmup + measure + drain; snapshot doubles seed size; 2 GB reserve)

- [ ] **Step 1: Write failing tests** with fixture `/proc/stat` and `/proc/diskstats` text:

```swift
@Test func perCoreBusyFromTwoSnapshots() { /* two fixtures 1 s apart → core0 0.90, core1 0.20 */ }
@Test func diskAwaitAndQueue() { /* fixture deltas → await 4.0 ms, queue 0.5 */ }
@Test func fourKBCatchUpReducesCorpusToFit() {
    #expect(Budget.check(freeBytes: 6_000_000_000, cell: .fixture(kind: .catchUp, eventSize: 4096)) == .reduceCorpus(to: 450_000))
}
@Test func headlineRebuildL10000FitsTheJobLimit() { #expect(Budget.estimatedMinutes(.fixture(kind: .rebuild, streamLength: 10000, tier: .headline), clients: 3) <= 330) }
```

(Exact expected numbers follow from the formula above; the implementer fixes them in the fixtures.)

- [ ] **Step 2: Run** — FAIL. **Step 3: Implement.** **Step 4: Run** — PASS.
- [ ] **Step 5: Commit** `[ADD] per-core, disk and projection headroom monitor, and per-cell disk and time budget`

### Task 9: Trial runner, persistent subscription progress and ghz adapter

**Files:**
- Create: `Benchmarks/Live/orchestrator/TrialRunner.swift`, `PersistentProgress.swift`, `GhzAdapter.swift`, `main.swift`
- Create: `Benchmarks/Live/drivers/ghz/append.json`, `read.json` (ghz call configs)
- Test: `Benchmarks/Live/Tests/LiveOrchestratorTests/TrialRunnerTests.swift`, `GhzAdapterTests.swift`, `PersistentProgressLiveTests.swift` (Docker-gated)

**Interfaces:**
- Consumes: Tasks 1–8
- Produces:
  - `struct DriverSpec: Codable { name: String; command: [String] }` (Swift binary, `dotnet <dll>`, or `ghz`)
  - `struct TrialRunner { func runCell(_ cell: Cell, drivers: [DriverSpec], rounds: Int) async throws -> CellResult }` — for each round, rotate driver order (round r starts at index r mod n); for each rate and driver run spec lifecycle steps 1–7 (restore snapshot → drop caches → start server → wait `$by_category` → warmup → measure → drain → validate/collect), with the monitor running during measure.
  - Every driver process is launched as `taskset -c 2,3 <command…>` on Linux (plain command on macOS); the server is pinned by `ServerControl`'s `cpuset`.
  - Before each step it checks free disk against `Budget`; if short, the cell stops with `abortedReason` naming the step, and results so far are kept.
  - A driver that does not exit within warmup + measure + drain + 60 s is killed and recorded as an error.
  - `struct CellResult: Codable { cell: Cell; trials: [TrialRecord]; metadata: RunMetadata; abortedReason: String? }`, `struct TrialRecord: Codable { round: Int; rate: Double; driver: String; result: TrialResult?; histogram: HistogramFile?; headroom: HeadroomSample?; serverAckedProgress: Int64?; error: String? }`
  - `PersistentProgress`: orchestrator creates the group per trial (name `g<round>-<rate>-<driver>`, `settings.resolveLink = true`, `consumerStrategy = .roundRobin`, `checkpointCount = 1...1000`, `revision = .start`, identical for all clients) and reads acknowledged progress after the drain.
  - `GhzAdapter.convert(report: Data, cellId: String, rate: Double) throws -> (TrialResult, HistogramFile)` with `timing = .rpcStart`.
  - CLI: `LiveOrchestrator run-cell --cell <id> --drivers <drivers.json> --out <dir>` and `LiveOrchestrator trend --out <dir>` (one fixed middle rate per scenario, Swift only, 1 round, writes `bmf.json`).

- [ ] **Step 1: Write the probe test first** — it decides which `SubscriptionInfo` field is acknowledged progress:

```swift
@Test(.enabled(if: docker)) func checkpointAdvancesOnlyOnAck() async throws {
    // create group as above on $ce-probe; append 100 events; subscribe, receive all, ack none, wait 5 s:
    //   record info.totalItems and info.lastCheckpointedEventPosition
    // then ack all 100, wait checkpointAfter + 2 s: record again.
    // Expect: lastCheckpointedEventPosition moves only after acks. If instead another field does,
    // change PersistentProgress to use it and document the finding in Benchmarks/Live/docs/driver-contract.md.
}
```

- [ ] **Step 2: Write failing unit tests**

```swift
@Test func rotationStartsEachRoundWithTheNextDriver() { /* 3 drivers, 3 rounds → orders ABC, BCA, CAB */ }
@Test func crashingDriverIsRecordedAndRunContinues() async throws {
    // DriverSpec(command: ["/bin/sh", "-c", "echo boom >&2; exit 3"]) between two fake drivers that write a valid result
    // → TrialRecord.error contains "exit 3" and "boom"; the other two records have results; runCell returns normally
}
@Test func ghzReportConvertsWithRpcStartTiming() throws { /* fixture ghz JSON with details → scheduled == count, timing == .rpcStart */ }
```

(TrialRunner takes the server and monitor behind small protocols so these tests run without Docker.)

- [ ] **Step 3: Run** — FAIL. **Step 4: Implement**, including `PersistentProgress` per the probe's finding. **Step 5: Run** — PASS (unit tests; probe with `LIVE_BENCH_DOCKER=1`).
- [ ] **Step 6: Commit** `[ADD] trial runner with per-trial state reset and rotation, acknowledged progress, ghz adapter`

### Task 10: .NET driver

**Files:**
- Create: `Benchmarks/Live/drivers/dotnet/LiveDriver.DotNet.csproj` (net8.0, `RestorePackagesWithLockFile=true`, exact `KurrentDB.Client` version = latest stable at implementation time, `HdrHistogram` 2.5.0), `Program.cs`, `Scenarios.cs`, `OpenLoop.cs`, `packages.lock.json`
- Test: `Benchmarks/Live/Tests/LiveOrchestratorTests/ContractConformanceLiveTests.swift` (Docker-gated, runs against both drivers)

**Interfaces:**
- Consumes: the contract in `Benchmarks/Live/docs/driver-contract.md` (Task 5); `EffectiveScenario` JSON (Task 1).
- Produces: `dotnet Benchmarks/Live/drivers/dotnet/bin/Release/net8.0/LiveDriver.DotNet.dll run|version ...` with identical behaviour per kind to Task 6 (same default client settings, link resolution on for catch-up, ack per event, redelivery counting, percentiles over all attempts, histogram in microseconds).

- [ ] **Step 1: Write the failing conformance tests** — parameterised over `[.swift, .dotnet]`:

```swift
@Test(.enabled(if: docker), arguments: [Client.swift, .dotnet])
func everyKindProducesAValidatedResult(client: Client) async throws {
    for kind in ScenarioKind.allCases {
        let r = try await runDriver(client, scenario: .fixture(kind: kind, rate: 20, measureSeconds: 3))
        #expect(r.timing == .scheduled)
        #expect(r.validation.receivedEvents == r.validation.expectedEvents)
        #expect(r.validation.payloadSizesOk)
    }
}
@Test(.enabled(if: docker), arguments: [Client.swift, .dotnet])
func versionReportsExactClientVersion(client: Client) async throws { /* clientVersion matches the pinned NuGet version / SDK commit */ }
```

- [ ] **Step 2: Run** — FAIL for `.dotnet`. **Step 3: Implement** (`dotnet build -c Release`). **Step 4: Run** — PASS for both.
- [ ] **Step 5: Commit** `[ADD] .NET driver on KurrentDB.Client implementing the shared driver contract`

### Task 11: Report, results bundle, metadata and Bencher output

**Files:**
- Create: `Benchmarks/Live/orchestrator/Report.swift`, `Metadata.swift`, `Merge.swift`, `BMF.swift`
- Test: `Benchmarks/Live/Tests/LiveOrchestratorTests/ReportTests.swift`, `MetadataTests.swift`

**Interfaces:**
- Consumes: `CellResult` (Task 9), `estimateRatio`, `isSustained`, `hasHeadroom` (Task 4), `percentile` (Task 2)
- Produces:
  - `RunMetadata: Codable` — SDK commit SHA, harness commit SHA, Swift toolchain, .NET runtime, `KurrentDB.Client` version, ghz version, build flags, server image + digest + effective server config, effective scenario (rates, durations, cap, deadline, seed), runner image version, CPU model, `corpusReducedTo`. **No hostname, IPs or usernames.**
  - `LiveOrchestrator merge --in <dir of cell results> --out <bundle dir>` → `Benchmarks/Live/results/<YYYY-MM-DD>-<server version>/` layout: one folder per cell with raw files, `metadata.json`, `report.html`.
  - `Report.render(_ cells: [CellResult]) -> String` — self-contained HTML, inline SVG, both themes; per cell: rate-step table with sustained/system-limited labels, percentiles (censored as "> deadline"), ratio + CI + verdict per metric (oriented, with the direction stated), client CPU per 1,000 ops and RSS, ghz shown separately as "transport reference", loopback disclaimer, corpus reduction note when present. Never divides numbers from different cells.
  - `BMF.trend(_ result: CellResult) -> Data` — Bencher Metric Format with measures `latency` (p50/p99 as value/upper) and `throughput`.

- [ ] **Step 1: Write failing tests**

```swift
@Test func censoredPercentileRendersAsDeadline() { #expect(Report.render([.fixtureWithLosses]).contains("&gt; deadline")) }
@Test func systemLimitedStepGetsNoVerdict() { /* fixture where hasHeadroom false at top rate → that row says "system-limited" and has no verdict */ }
@Test func ghzLatencyNeverInARatio() { /* rendered ratio rows mention only Swift and .NET */ }
@Test func metadataHasNoHostIdentity() throws {
    let json = try String(data: JSONEncoder().encode(RunMetadata.collect(environment: ["HOSTNAME": "secret-box", "USER": "alice"])), encoding: .utf8)!
    #expect(!json.contains("secret-box")); #expect(!json.contains("alice"))
    #expect(json.range(of: #"\b(10|192\.168|172\.(1[6-9]|2\d|3[01]))\.\d+\.\d+"#, options: .regularExpression) == nil)
}
@Test func reportHasNoNaN() { #expect(!Report.render([.fixtureAllFailed]).contains("NaN")) }
```

- [ ] **Step 2: Run** — FAIL. **Step 3: Implement.** **Step 4: Run** — PASS.
- [ ] **Step 5: Commit** `[ADD] self-contained HTML report, results bundle with reproducibility metadata, and Bencher output`

### Task 12: Workflows and documentation

**Files:**
- Create: `.github/workflows/live-benchmarks.yml`
- Modify: `BENCHMARKS.md` (new "Live benchmarks" section: what runs, how to trigger, how results land via PR, link target for the published report)
- Create: `Benchmarks/Live/README.md` (local run: `LIVE_BENCH_DOCKER=1`, building drivers, running one cell)

**Interfaces:**
- Consumes: `LiveOrchestrator run-cell`, `trend`, `merge` (Tasks 9, 11); `config/cells.json` (Task 1)
- Produces:
  - Job `cells` (on `workflow_dispatch` with optional input `cells` = comma-separated ids, and on `push: tags: ['*']`): a `prepare` job emits the cell id list as a JSON array (from `cells.json`, filtered by input) → matrix over ids; each job: `runs-on: ubuntu-latest`, `timeout-minutes: 350`, `permissions: contents: read`; free disk (remove `/usr/local/lib/android`, `/opt/ghc`, `/usr/local/share/boost`), setup Swift 6.4 (same pinned `SwiftyLab/setup-swift` SHA as `benchmarks.yml`), setup .NET 8 (`actions/setup-dotnet` pinned by SHA), install ghz v0.120.0 from its release tarball with checksum check, build drivers in release, `LiveOrchestrator run-cell`, upload `cell-<id>` artifact.
  - Job `merge` (needs `cells`, `if: always()`): downloads all cell artifacts, `LiveOrchestrator merge`, uploads `live-benchmark-report` artifact (bundle + `report.html`). It commits nothing.
  - Job `trend` (on `schedule: cron: '0 18 * * *'`, main only): Swift only, `LiveOrchestrator trend`, `bencher run --project gradyzhuo-s-project --branch main --testbed ubuntu-latest-live --adapter json --file bmf.json --threshold-measure latency --threshold-test t_test --threshold-min-sample-size 10 --threshold-max-sample-size 64 --threshold-upper-boundary 0.99 --thresholds-reset` with `BENCHER_API_KEY` from secrets — **without** `--error-on-alert`.
  - All third-party actions pinned to full commit SHAs with the version in a trailing comment, as in `benchmarks.yml`.

- [ ] **Step 1: Validate** the workflow with `actionlint .github/workflows/live-benchmarks.yml` (install via Homebrew if missing) — expect no findings.
- [ ] **Step 2: Dry-run** one small cell locally: `LIVE_BENCH_DOCKER=1 swift run --package-path Benchmarks/Live -c release LiveOrchestrator run-cell --cell persistent-300-tls --drivers Benchmarks/Live/config/drivers.local.json --out /tmp/live-dry` with a temporary override of 1 round, 1 rate, 5 s measure (flag `--smoke`) — expect `report.html` produced with Swift and .NET rows and no `NaN`.
- [ ] **Step 3: Private-address check** `git grep -nE "\b(10|192\.168|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]+\.[0-9]+" -- Benchmarks .github BENCHMARKS.md` — expect no matches (loopback `127.0.0.1` is fine). Also confirm no internal product or host names appear in results or metadata.
- [ ] **Step 4: Commit** `[ADD] live benchmark workflows: per-cell comparison jobs, report merge, nightly Swift trend to Bencher`
- [ ] **Step 5: Push the branch and trigger** `gh workflow run live-benchmarks.yml -f cells=append-latency-300-tls --ref <branch>` (only after the maintainer agrees to push) — expect the job to finish under 350 minutes with a report artifact.
