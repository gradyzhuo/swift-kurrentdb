import Foundation
@testable import LiveBenchCore
@testable import LiveOrchestrator
import Synchronization
import Testing

/// The trial runner against a fake server and monitor and shell-script drivers, so no Docker is needed.
@Suite("Trial runner")
struct TrialRunnerTests {
    @Test func rotationStartsEachRoundWithTheNextDriver() {
        let drivers = ["A", "B", "C"].map { DriverSpec(name: $0, command: ["true"]) }
        let orders = (0..<4).map { round in TrialRunner.order(drivers, round: round).map(\.name).joined() }
        #expect(orders == ["ABC", "BCA", "CAB", "ABC"])
        #expect(TrialRunner.order([], round: 3).isEmpty)
    }

    @Test func crashingDriverIsRecordedAndRunContinues() async throws {
        let fixture = try Fixture()
        let drivers = [
            fixture.goodDriver("A"),
            DriverSpec(name: "crash", command: ["/bin/sh", "-c", "echo boom >&2; exit 3"]),
            fixture.goodDriver("C"),
        ]
        let result = try await fixture.runner().runCell(fixture.cell, drivers: drivers, rounds: 1)

        #expect(result.abortedReason == nil)
        #expect(result.trials.map(\.driver) == ["A", "crash", "C"])
        let crashed = result.trials[1]
        #expect(crashed.result == nil)
        #expect(crashed.error?.contains("exit 3") == true)
        #expect(crashed.error?.contains("boom") == true)
        for record in [result.trials[0], result.trials[2]] {
            #expect(record.error == nil)
            #expect(record.result?.succeeded == 20)
            #expect(record.histogram?.buckets.isEmpty == false)
        }
        // Every trial starts from the snapshot on a fresh server and ends with the server stopped.
        #expect(fixture.server.calls.filter { $0 == "restore" }.count == 3)
        #expect(fixture.server.calls.filter { $0 == "stop" }.count == 3)
        #expect(fixture.server.calls.first == "prepare")
    }

    @Test func roundsRotateAndEveryRateRunsForEveryDriver() async throws {
        let fixture = try Fixture()
        var cell = fixture.cell
        cell.rates = [20, 50]
        let drivers = [fixture.goodDriver("A"), fixture.goodDriver("B")]
        let result = try await fixture.runner().runCell(cell, drivers: drivers, rounds: 2)
        let order = result.trials.map { "\($0.round):\(Int($0.rate)):\($0.driver)" }
        #expect(order == ["0:20:A", "0:20:B", "0:50:A", "0:50:B", "1:20:B", "1:20:A", "1:50:B", "1:50:A"])
    }

    @Test func driverThatHangsIsKilledAndRecorded() async throws {
        let fixture = try Fixture()
        let drivers = [DriverSpec(name: "hang", command: ["/bin/sh", "-c", "echo stuck >&2; exec sleep 30"]), fixture.goodDriver("B")]
        var runner = fixture.runner()
        runner.killGraceSeconds = 1
        let clock = ContinuousClock()
        let started = clock.now
        let result = try await runner.runCell(fixture.cell, drivers: drivers, rounds: 1)
        #expect(started.duration(to: clock.now) < .seconds(20))
        #expect(result.trials[0].error?.contains("did not exit") == true)
        #expect(result.trials[0].error?.contains("stuck") == true)
        #expect(result.trials[1].result != nil)
    }

    @Test func payloadSizeMismatchFailsTheTrialButKeepsTheResult() async throws {
        let fixture = try Fixture()
        var bad = fixture.result
        bad.validation.payloadSizesOk = false
        let drivers = [try fixture.driver("bad", writing: bad)]
        let result = try await fixture.runner().runCell(fixture.cell, drivers: drivers, rounds: 1)
        #expect(result.trials[0].result != nil)
        #expect(result.trials[0].error?.contains("payload") == true)
    }

    @Test func catchUpPhaseOneShortfallFailsTheTrial() {
        var scenario = EffectiveScenario.fixture(kind: .catchUp)
        scenario.cellId = "c"
        var result = TrialResult.fixture
        result.cellId = "c"
        result.targetRate = scenario.rate
        result.scheduled = 0; result.succeeded = 0; result.failed = 0; result.dropped = 0; result.timedOut = 0
        result.catchUpSeconds = nil
        result.validation = Validation(expectedEvents: 1000, receivedEvents: 400, payloadSizesOk: true)
        #expect(TrialRunner.hardFailure(result, scenario: scenario)?.contains("400 of 1000") == true)
        result.catchUpSeconds = 3
        #expect(TrialRunner.hardFailure(result, scenario: scenario) == nil)
    }

    @Test func liveWriteShortfallIsReportedNotFailed() {
        var scenario = EffectiveScenario.fixture(kind: .persistentSubscription)
        scenario.cellId = "p"
        var result = TrialResult.fixture
        result.cellId = "p"
        result.targetRate = scenario.rate
        result.validation = Validation(expectedEvents: 1195, receivedEvents: 1190, payloadSizesOk: true)
        #expect(TrialRunner.hardFailure(result, scenario: scenario) == nil)
    }

    @Test func rebuildCountMismatchFailsTheTrial() {
        var scenario = EffectiveScenario.fixture(kind: .rebuild)
        scenario.cellId = "r"
        var result = TrialResult.fixture
        result.cellId = "r"
        result.targetRate = scenario.rate
        result.validation = Validation(expectedEvents: 11_900, receivedEvents: 11_895, payloadSizesOk: true)
        #expect(TrialRunner.hardFailure(result, scenario: scenario)?.contains("11895") == true)
    }

    @Test func persistentSubscriptionTrialsGetFreshGroupsAndAcknowledgedProgress() async throws {
        let fixture = try Fixture()
        var cell = fixture.cell
        cell.kind = .persistentSubscription
        var written = fixture.result
        written.validation = Validation(expectedEvents: 20, receivedEvents: 20, payloadSizesOk: true)
        fixture.server.ackedProgress = 18
        let result = try await fixture.runner().runCell(cell, drivers: [try fixture.driver("A", writing: written)], rounds: 1)
        #expect(result.trials[0].serverAckedProgress == 18)
        #expect(result.trials[0].error == nil)
        #expect(fixture.server.calls.contains("groups bench g0-20-A"))
        #expect(fixture.server.calls.contains("acked bench g0-20-A 20"))
    }

    @Test func diskShortfallStopsTheCellAndKeepsEarlierResults() async throws {
        let fixture = try Fixture()
        // Enough for the cell check and the first trial, then nothing.
        fixture.server.freeBytes = [Budget.githubRunnerFreeBytes, Budget.githubRunnerFreeBytes, 1_000]
        let drivers = [fixture.goodDriver("A"), fixture.goodDriver("B")]
        let result = try await fixture.runner().runCell(fixture.cell, drivers: drivers, rounds: 1)
        #expect(result.trials.count == 1)
        #expect(result.trials[0].result != nil)
        #expect(result.abortedReason?.contains("disk") == true)
        #expect(result.abortedReason?.contains("driver B") == true)
    }

    @Test func serverThatNeverGetsReadyEndsTheCellWithAReason() async throws {
        let fixture = try Fixture()
        fixture.server.failReady = true
        let result = try await fixture.runner().runCell(fixture.cell, drivers: [fixture.goodDriver("A"), fixture.goodDriver("B")], rounds: 1)
        #expect(result.abortedReason?.contains("wait ready") == true)
        #expect(result.trials.count == 1)
        #expect(result.trials[0].result == nil)
        #expect(fixture.server.calls.last == "stop")
    }

    @Test func cellOverTheJobLimitIsRefused() async throws {
        let fixture = try Fixture()
        var cell = fixture.cell
        cell.rates = Array(repeating: 100, count: 60)
        cell.rounds = 5
        let result = try await fixture.runner().runCell(cell, drivers: [fixture.goodDriver("A"), fixture.goodDriver("B")], rounds: 5)
        #expect(result.trials.isEmpty)
        #expect(result.abortedReason?.contains("330") == true)
        #expect(fixture.server.calls.isEmpty)
    }

    @Test func scenarioFollowsTheSeedManifestAndNamingRules() {
        let manifest = SeedManifest(rebuildStreams: ["bench-0", "bench-1"], catchUpCategory: nil, catchUpEvents: 0, lastCommitPosition: 1, lastPreparePosition: 1, corpusReducedTo: nil)
        let rebuild = Cell(id: "rebuild-300-tls-L10", kind: .rebuild, eventSize: 300, tls: true, streamLength: 10, tier: .headline, rates: [100], rounds: 5)
        let s = TrialRunner.scenario(cell: rebuild, manifest: manifest, rate: 100, round: 2, driver: "swift", phases: .standard, category: "bench", seed: 42)
        #expect(s.streamPrefix == "bench" && s.category == "bench")
        #expect(s.rebuildStreams == ["bench-0", "bench-1"] && s.streamCount == 2 && s.streamLength == 10)
        #expect(s.warmupSeconds == Budget.warmupSeconds && s.measureSeconds == Budget.measureSeconds && s.drainSeconds == Budget.drainSeconds)
        #expect(s.deadlineMillis == 5000 && s.inFlightCap == 256 && s.seed == 42 && s.metadataSize == 60)
        #expect(s.groupName == nil)

        let persistent = Cell(id: "persistent-300-tls-c4", kind: .persistentSubscription, eventSize: 300, tls: true, streamLength: nil, tier: .appendix, rates: [1000], rounds: 3, consumers: 4)
        let p = TrialRunner.scenario(cell: persistent, manifest: manifest, rate: 1000, round: 1, driver: "dotnet", phases: .standard, category: "bench", seed: 42)
        #expect(p.groupName == "g1-1000-dotnet" && p.consumers == 4 && p.rebuildStreams == nil)

        let throughput = Cell(id: "t", kind: .appendThroughput, eventSize: 300, tls: true, streamLength: nil, tier: .headline, rates: [20], rounds: 5)
        let t = TrialRunner.scenario(cell: throughput, manifest: manifest, rate: 20, round: 0, driver: "swift", phases: .smoke, category: "bench", seed: 42)
        #expect(t.batchSize == 50 && t.streamCount == 100_000 && t.warmupSeconds == 5 && t.measureSeconds == 5)

        var catchUpManifest = manifest
        catchUpManifest.catchUpCategory = "bench"
        catchUpManifest.catchUpEvents = 341_000
        let catchUp = Cell(id: "c", kind: .catchUp, eventSize: 4096, tls: true, streamLength: nil, tier: .appendix, rates: [250], rounds: 3)
        #expect(TrialRunner.scenario(cell: catchUp, manifest: catchUpManifest, rate: 250, round: 0, driver: "swift", phases: .standard, category: "bench", seed: 42).catchUpExpectedEvents == 341_000)
    }

    @Test func serverThatDiesDuringATrialFailsItAndEndsTheCell() async throws {
        let fixture = try Fixture()
        fixture.server.failStop = true
        let result = try await fixture.runner().runCell(fixture.cell, drivers: [fixture.goodDriver("A"), fixture.goodDriver("B")], rounds: 1)
        #expect(result.trials.count == 1)
        let trial = result.trials[0]
        #expect(trial.result != nil) // kept for the record, but the trial is failed
        #expect(trial.error?.hasPrefix("server: stop server after the trial failed") == true)
        #expect(trial.error?.contains("137") == true)
        #expect(result.abortedReason?.contains("driver A") == true)
        #expect(result.abortedReason?.contains("stop server") == true)
    }

    @Test func monitorWindowStartsAtTheDriversMarker() async throws {
        let fixture = try Fixture()
        // The driver keeps running 2 s after its marker, far longer than the 0.2 s window, so a loaded host cannot
        // make the window end at the driver's exit instead.
        let marked = try fixture.driver("A", writing: fixture.result, before: "sleep 0.6 && echo progress >&2 && echo LIVE_BENCH_MEASURE_START >&2 && sleep 2")
        let clock = ContinuousClock()
        let launched = clock.now
        let result = try await fixture.runner().runCell(fixture.cell, drivers: [marked], rounds: 1)
        #expect(result.trials[0].error == nil)
        #expect(result.trials[0].headroom != nil)
        #expect(result.trials[0].notes == nil)
        let start = try #require(fixture.monitor.starts.first)
        let stop = try #require(fixture.monitor.stops.first)
        #expect(launched.duration(to: start) >= .milliseconds(550))
        // measureSeconds (0.2 s) after the marker, not at driver exit (2 s after it).
        #expect(start.duration(to: stop) >= .milliseconds(190) && start.duration(to: stop) < .milliseconds(1500))
        // The actual events written replace the estimate.
        #expect(result.trials[0].headroom?.eventsWritten == 20)
    }

    @Test func persistentSubscriptionAckedProgressIsReadAtTheWindowEnd() async throws {
        let fixture = try Fixture()
        var cell = fixture.cell
        cell.kind = .persistentSubscription
        var written = fixture.result
        written.validation = Validation(expectedEvents: 20, receivedEvents: 20, payloadSizesOk: true)
        fixture.server.ackedProgress = 20
        fixture.server.ackedNow = 17
        let driver = try fixture.driver("A", writing: written, before: "echo LIVE_BENCH_MEASURE_START >&2 && sleep 2")
        let result = try await fixture.runner().runCell(cell, drivers: [driver], rounds: 1)
        let trial = result.trials[0]
        #expect(trial.error == nil)
        #expect(trial.serverAckedAtWindowEnd == 17)
        #expect(trial.serverAckedProgress == 20)
        #expect(fixture.server.calls.contains("acked now bench g0-20-A"))
        // Read once, at marker + measureSeconds (0.2 s), long before the driver exits.
        let start = try #require(fixture.monitor.starts.first)
        let read = try #require(fixture.server.ackedNowReads.first)
        #expect(fixture.server.ackedNowReads.count == 1)
        #expect(start.duration(to: read) >= .milliseconds(190) && start.duration(to: read) < .milliseconds(1500))
    }

    @Test func harnessFloorsRunOncePerDriverAndRateBeforeSeeding() async throws {
        let fixture = try Fixture()
        var cell = fixture.cell
        cell.rates = [20, 50]
        let floorJSON = #"{"rate":RATE,"seconds":0.1,"scheduled":5,"succeeded":5,"p50Micros":7,"p99Micros":90,"p999Micros":95,"maxMicros":99,"cpuSeconds":0.01,"maxRssBytes":1000,"runtime":"fake"}"#
        // `<command> floor --rate <r> --seconds <s> --warmup <w>`: $0 is "floor", $2 the rate.
        let answering = "if [ \"$0\" = floor ]; then echo '\(floorJSON)' | sed \"s/RATE/$2/\"; exit 0; fi"
        let good = try fixture.driver("A", writing: fixture.result, before: "true", prefix: answering)
        let broken = try fixture.driver("B", writing: fixture.result, before: "true", prefix: "if [ \"$0\" = floor ]; then echo nope >&2; exit 2; fi")
        var runner = fixture.runner()
        runner.floor = FloorSettings(warmupSeconds: 0.05, seconds: 0.1)
        let result = try await runner.runCell(cell, drivers: [good, broken, DriverSpec(name: "ghz", command: ["false"])], rounds: 1)
        let floors = try #require(result.metadata.harnessFloors)
        #expect(floors.map { "\($0.driver)@\(Int($0.rate))" } == ["A@20", "A@50", "B@20", "B@50"])
        #expect(floors[0].floor?.p99Micros == 90 && floors[1].floor?.rate == 50)
        #expect(floors[2].floor == nil && floors[2].error?.contains("nope") == true)
        // A broken floor does not stop the cell.
        #expect(result.abortedReason == nil)
        #expect(result.trials.filter { $0.driver != "ghz" }.allSatisfy { $0.error == nil })
    }

    @Test func noTrialStartsPastTheJobTimeGuard() async throws {
        let fixture = try Fixture()
        var runner = fixture.runner()
        let started = Date()
        runner.jobStarted = started.addingTimeInterval(-339 * 60)
        // The first trial starts at 339 minutes; the clock then reads 341 minutes.
        let calls = Mutex(0)
        runner.now = {
            calls.withLock { $0 += 1; return $0 } == 1 ? started : started.addingTimeInterval(2 * 60)
        }
        let result = try await runner.runCell(fixture.cell, drivers: [fixture.goodDriver("A"), fixture.goodDriver("B")], rounds: 1)
        #expect(result.trials.map(\.driver) == ["A"])
        #expect(result.abortedReason?.contains("340") == true)
        #expect(result.abortedReason?.contains("driver B") == true)
    }

    @Test func driverWithoutMarkerHasNoHeadroomAndANote() async throws {
        let fixture = try Fixture()
        let result = try await fixture.runner().runCell(fixture.cell, drivers: [fixture.goodDriver("A")], rounds: 1)
        #expect(result.trials[0].error == nil)
        #expect(result.trials[0].headroom == nil)
        #expect(result.trials[0].notes?.first?.contains("LIVE_BENCH_MEASURE_START") == true)
        #expect(fixture.monitor.starts.isEmpty)
    }

    @Test func progressIsReportedAfterEveryTrial() async throws {
        let fixture = try Fixture()
        let seen = Mutex<[Int]>([])
        var runner = fixture.runner()
        runner.onProgress = { partial in seen.withLock { $0.append(partial.trials.count) } }
        _ = try await runner.runCell(fixture.cell, drivers: [fixture.goodDriver("A"), fixture.goodDriver("B")], rounds: 2)
        #expect(seen.withLock { $0 } == [1, 2, 3, 4])
    }

    @Test func markerIsOnlyAWholeLine() async throws {
        let fixture = try Fixture()
        let file = fixture.directory.appendingPathComponent("stderr.log")
        try Data("info: x LIVE_BENCH_MEASURE_START later\nLIVE_BENCH_MEASURE_STAR".utf8).write(to: file)
        let waiting = Task { await MeasureMarker.wait(in: file, poll: .milliseconds(5)) }
        try await Task.sleep(for: .milliseconds(100))
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("T\n".utf8)) // completes the split marker line
        try handle.close()
        #expect(await waiting.value)

        let other = fixture.directory.appendingPathComponent("other.log")
        try Data("no marker here\nLIVE_BENCH_MEASURE_START_NOT\n".utf8).write(to: other)
        let never = Task { await MeasureMarker.wait(in: other, poll: .milliseconds(5)) }
        try await Task.sleep(for: .milliseconds(100))
        never.cancel()
        #expect(await never.value == false)
    }

    @Test func ghzOnlyRunsForAppendAndRebuildCells() {
        let drivers = [DriverSpec(name: "swift", command: ["x"]), DriverSpec(name: "ghz", command: ["ghz"])]
        #expect(TrialRunner.applicableDrivers(drivers, kind: .appendLatency).map(\.name) == ["swift", "ghz"])
        #expect(TrialRunner.applicableDrivers(drivers, kind: .rebuild).map(\.name) == ["swift", "ghz"])
        #expect(TrialRunner.applicableDrivers(drivers, kind: .persistentSubscription).map(\.name) == ["swift"])
        #expect(TrialRunner.applicableDrivers(drivers, kind: .catchUp).map(\.name) == ["swift"])
    }

    @Test func driverLaunchIsPinnedOnlyWhenCPUsAreGiven() {
        #expect(TrialRunner.launchCommand(["dotnet", "d.dll"], cpus: "2,3") == ["taskset", "-c", "2,3", "dotnet", "d.dll"])
        #expect(TrialRunner.launchCommand(["dotnet", "d.dll"], cpus: nil) == ["dotnet", "d.dll"])
    }
}

// MARK: - Fakes

/// A work directory with a valid `result.json`/`histogram.json` and helpers to build shell drivers that copy them.
private struct Fixture {
    let directory: URL
    let server = FakeServer()
    let monitor = FakeMonitor()
    let cell = Cell(id: "fixture-appendLatency-300", kind: .appendLatency, eventSize: 300, tls: false, streamLength: nil, tier: .headline, rates: [20], rounds: 1)
    var result: TrialResult {
        var r = TrialResult.fixture
        r.client = "fake"
        r.scheduled = 20; r.succeeded = 20; r.failed = 0; r.dropped = 0; r.timedOut = 0
        r.validation = Validation(expectedEvents: 20, receivedEvents: 20, payloadSizesOk: true)
        return r
    }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("trial-runner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(HistogramFile(buckets: [[100, 15], [250, 5]])).write(to: directory.appendingPathComponent("histogram.json"))
    }

    func runner() -> TrialRunner {
        var runner = TrialRunner(server: server, monitor: monitor, workDirectory: directory.appendingPathComponent("out"))
        runner.phases = TrialPhases(warmupSeconds: 0, measureSeconds: 0.2, drainSeconds: 0)
        runner.driverCPUs = nil
        runner.floor = nil
        runner.log = { _ in }
        return runner
    }

    func goodDriver(_ name: String) -> DriverSpec {
        // swiftlint:disable:next force_try
        try! driver(name, writing: result)
    }

    /// A driver that writes `result` (with the trial's rate) and the fixture histogram into `--out` (argument 6),
    /// running `before` first (e.g. sleeps and the measure-start marker).
    func driver(_ name: String, writing result: TrialResult, before: String = "true", prefix: String = "true") throws -> DriverSpec {
        let file = directory.appendingPathComponent("result-\(name).json")
        try JSONEncoder().encode(result).write(to: file)
        let histogram = directory.appendingPathComponent("histogram.json").path
        // The runner appends: run --scenario <file> --connection <cs> --out <dir>  ($0 ... $6). The fake rewrites the
        // rate from the scenario so any rate step validates.
        let script = """
        \(prefix); \(before) && mkdir -p "$6" && rate=$(sed -n 's/.*"rate":\\([0-9.]*\\).*/\\1/p' "$2") && \
        sed "s/\\"targetRate\\":[0-9.]*/\\"targetRate\\":$rate/" '\(file.path)' > "$6/result.json" && cp '\(histogram)' "$6/histogram.json"
        """
        return DriverSpec(name: name, command: ["/bin/sh", "-c", script])
    }
}

private final class FakeServer: TrialServer, Sendable {
    private let state = Mutex<(calls: [String], free: [Int64], acked: Int64, failReady: Bool, failStop: Bool)>(([], [], 0, false, false))
    private let now = Mutex<(acked: Int64, reads: [ContinuousClock.Instant])>((0, []))

    var ackedNow: Int64 {
        get { now.withLock { $0.acked } }
        set { now.withLock { $0.acked = newValue } }
    }
    var ackedNowReads: [ContinuousClock.Instant] { now.withLock { $0.reads } }

    var calls: [String] { state.withLock { $0.calls } }
    var freeBytes: [Int64] {
        get { state.withLock { $0.free } }
        set { state.withLock { $0.free = newValue } }
    }
    var ackedProgress: Int64 {
        get { state.withLock { $0.acked } }
        set { state.withLock { $0.acked = newValue } }
    }
    var failReady: Bool {
        get { state.withLock { $0.failReady } }
        set { state.withLock { $0.failReady = newValue } }
    }

    var failStop: Bool {
        get { state.withLock { $0.failStop } }
        set { state.withLock { $0.failStop = newValue } }
    }

    private func note(_ call: String) { state.withLock { $0.calls.append(call) } }

    let connectionString = "kurrentdb://127.0.0.1:1?tls=false"
    let ghzTarget = GhzTarget(host: "127.0.0.1:1", caFile: nil, authorization: "Basic x")

    func freeDiskBytes() throws -> Int64 {
        state.withLock { s in s.free.isEmpty ? Budget.githubRunnerFreeBytes : s.free.removeFirst() }
    }
    func prepare(cell: Cell, corpusOverride: Int?) async throws -> SeedManifest {
        note("prepare")
        return SeedManifest(rebuildStreams: [], catchUpCategory: nil, catchUpEvents: 0, lastCommitPosition: 0, lastPreparePosition: 0, corpusReducedTo: nil)
    }
    func restoreSnapshot() throws { note("restore") }
    func dropCaches() throws { note("drop caches") }
    func start() async throws { note("start") }
    func waitReady() async throws {
        note("ready")
        if failReady { throw ServerError.notReady(reason: "fake") }
    }
    func waitForByCategory(_ manifest: SeedManifest) async throws { note("by category") }
    func createGroups(category: String, group: String) async throws { note("groups \(category) \(group)") }
    func acknowledgedProgress(category: String, group: String, expected: Int64) async throws -> Int64 {
        note("acked \(category) \(group) \(expected)")
        return ackedProgress
    }
    func acknowledgedProgressNow(category: String, group: String) async throws -> Int64 {
        note("acked now \(category) \(group)")
        return now.withLock { $0.reads.append(.now); return $0.acked }
    }
    func stop() throws {
        note("stop")
        if failStop { throw ServerError.uncleanStop(reason: "container exited with exit code 137") }
    }
    func serverMetadata() -> (image: String?, digest: String?, configuration: [String: String]?) { (nil, nil, nil) }
}

/// Records when its window starts and stops and returns a fixed sample.
private final class FakeMonitor: TrialMonitor, Sendable {
    private let events = Mutex<[(String, ContinuousClock.Instant)]>([])

    var starts: [ContinuousClock.Instant] { events.withLock { $0.filter { $0.0 == "start" }.map(\.1) } }
    var stops: [ContinuousClock.Instant] { events.withLock { $0.filter { $0.0 == "stop" }.map(\.1) } }

    func start() async { events.withLock { $0.append(("start", ContinuousClock.now)) } }
    func stop(eventsWritten: Int64) async -> HeadroomSample? {
        events.withLock { $0.append(("stop", ContinuousClock.now)) }
        return HeadroomSample(coreBusy: [0.5, 0.5], diskAwaitMillis: 1, diskQueueDepth: 0.1, projectionBufferedStart: 0, projectionBufferedEnd: 0, eventsWritten: eventsWritten, projectionCatchUpSeconds: 0.5)
    }
}
