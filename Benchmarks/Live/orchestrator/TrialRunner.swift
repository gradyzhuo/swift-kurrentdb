import Foundation
import LiveBenchCore
import Synchronization

/// A client under test: its name (`swift`, `dotnet`, `ghz`) and the command that starts it. In-process drivers get
/// `run --scenario <file> --connection <cs> --out <dir>` appended (driver contract); `ghz` is recognised by name and
/// driven through `GhzAdapter`. Relative paths resolve against the orchestrator's working directory.
struct DriverSpec: Codable, Sendable, Equatable {
    var name: String
    var command: [String]

    var isGhz: Bool { name == "ghz" }
}

/// One client's trial at one rate in one round.
struct TrialRecord: Codable, Sendable {
    var round: Int
    var rate: Double
    var driver: String
    /// The driver's `result.json`; kept even when `error` is set by a validation failure.
    var result: TrialResult?
    var histogram: HistogramFile?
    /// Server headroom over the measure window; nil when it could not be measured.
    var headroom: HeadroomSample?
    /// Persistent subscription: events of the measured group acknowledged as seen by the server (`PersistentProgress`),
    /// read after the driver exited. nil for other kinds or when unreadable.
    var serverAckedProgress: Int64?
    /// Set when the trial failed: the driver crashed, hung, wrote no readable result, or a hard validation failed.
    /// A failed trial is excluded from ratios.
    var error: String?
}

/// Everything one cell produced. `abortedReason` is set when the cell stopped early (refused, disk, server); the
/// trials before it are kept.
struct CellResult: Codable, Sendable {
    var cell: Cell
    var trials: [TrialRecord]
    var metadata: RunMetadata
    var abortedReason: String?
}

/// Lengths of a trial's phases.
struct TrialPhases: Sendable, Equatable {
    var warmupSeconds: Double
    var measureSeconds: Double
    var drainSeconds: Double

    static let standard = TrialPhases(warmupSeconds: Budget.warmupSeconds, measureSeconds: Budget.measureSeconds, drainSeconds: Budget.drainSeconds)
    /// `run-cell --smoke`.
    static let smoke = TrialPhases(warmupSeconds: 5, measureSeconds: 5, drainSeconds: Budget.drainSeconds)
}

/// The server side of a cell as the trial runner needs it (`CellServer` in production, a fake in tests).
protocol TrialServer: Sendable {
    var connectionString: String { get }
    var ghzTarget: GhzTarget { get }
    /// Free bytes on the file system holding the server's data directory and snapshot.
    func freeDiskBytes() throws -> Int64
    /// Once per cell: a fresh data directory, certificates, first start, seeding, clean stop and snapshot.
    func prepare(cell: Cell, corpusOverride: Int?) async throws -> SeedManifest
    func restoreSnapshot() throws
    func dropCaches() throws
    func start() async throws
    func waitReady() async throws
    func waitForByCategory(_ manifest: SeedManifest) async throws
    /// The trial's groups: `group` on `$ce-<category>` and `group + "w"` on `$ce-<category>w`.
    func createGroups(category: String, group: String) async throws
    /// `PersistentProgress.read` on `group` of `$ce-<category>`.
    func acknowledgedProgress(category: String, group: String, expected: Int64) async throws -> Int64
    func stop() throws
    /// Image, digest and effective configuration for `RunMetadata` (nil when unknown).
    func serverMetadata() -> (image: String?, digest: String?, configuration: [String: String]?)
}

/// The headroom monitor of the measure window (`Monitor` in production).
protocol TrialMonitor: Sendable {
    func start() async
    func stop(eventsWritten: Int64) async -> HeadroomSample?
}

extension Monitor: TrialMonitor {}

/// Runs one cell: seeding once, then for every round (driver order rotated), every rate and every driver one trial
/// from the identical seeded state.
///
/// Per trial: check free disk → restore the snapshot → drop the page cache → start the server → wait until ready →
/// wait for `$by_category` to reach the seed's last position → (persistent subscription: create the measured group
/// `g<round>-<rate>-<driver>` and its warmup twin) → launch the driver (pinned with `taskset` on Linux) with the
/// monitor sampling the measure window → driver exit → (persistent subscription: read acknowledged progress) → stop
/// the server → validate and record.
///
/// Failures: a driver that crashes, hangs or writes no readable result fails its trial, and the cell continues. A
/// hard validation failure (driver contract: payload sizes, rebuild counts, catch-up phase 1) fails the trial but
/// keeps its result. A server step that fails, or free disk below the next trial's need, ends the cell with
/// `abortedReason`; the trials so far are kept.
struct TrialRunner: Sendable {
    var server: any TrialServer
    var monitor: any TrialMonitor
    /// Trial files go to `<workDirectory>/trials/r<round>-<rate>-<driver>/`.
    var workDirectory: URL
    var phases = TrialPhases.standard
    var metadata = RunMetadata()
    /// CPUs the driver process is pinned to (`taskset -c`), nil for no pinning. Linux default: the two cores the
    /// server does not use (`ServerControl`'s default `cpuset` is `0,1`).
    #if os(Linux)
    var driverCPUs: String? = "2,3"
    #else
    var driverCPUs: String?
    #endif
    /// Grace after warmup + measure + drain before a driver is killed.
    var killGraceSeconds = 60.0
    /// Directory of the ghz call config templates (`drivers/ghz`).
    var ghzConfigDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("drivers/ghz")
    /// Stream prefix and category of the seeded and written streams (`Seeder.category`).
    var category = Seeder().category
    var seed = Seeder().payloadSeed
    var log: @Sendable (String) -> Void = { line in
        FileHandle.standardError.write(Data("[orchestrator] \(line)\n".utf8))
    }

    init(server: any TrialServer, monitor: any TrialMonitor, workDirectory: URL) {
        self.server = server
        self.monitor = monitor
        self.workDirectory = workDirectory
    }

    // MARK: - Cell

    func runCell(_ cell: Cell, drivers allDrivers: [DriverSpec], rounds: Int) async throws -> CellResult {
        let drivers = Self.applicableDrivers(allDrivers, kind: cell.kind)
        var metadata = self.metadata
        metadata.scenario = RunMetadata.ScenarioSettings(
            rates: cell.rates, rounds: rounds, warmupSeconds: phases.warmupSeconds, measureSeconds: phases.measureSeconds,
            drainSeconds: phases.drainSeconds, inFlightCap: Budget.inFlightCap, deadlineMillis: Budget.deadlineMillis, seed: seed,
            smoke: phases != .standard
        )
        var outcome = CellResult(cell: cell, trials: [], metadata: metadata, abortedReason: nil)

        var estimated = cell
        estimated.rounds = rounds
        let minutes = Budget.estimatedMinutes(estimated, clients: drivers.count)
        guard minutes <= Budget.jobLimitMinutes else {
            outcome.abortedReason = "refused: estimated \(Int(minutes.rounded(.up))) minutes exceeds the \(Int(Budget.jobLimitMinutes))-minute job limit"
            return outcome
        }

        var corpusOverride: Int?
        do {
            switch Budget.check(freeBytes: try server.freeDiskBytes(), cell: cell) {
            case .ok: break
            case let .reduceCorpus(to: events): corpusOverride = events
            case let .refuse(reason): outcome.abortedReason = "refused (disk): \(reason)"; return outcome
            }
        } catch {
            outcome.abortedReason = "disk check before seeding failed: \(error)"
            return outcome
        }

        log("\(cell.id): seeding")
        let manifest: SeedManifest
        do {
            manifest = try await server.prepare(cell: cell, corpusOverride: corpusOverride)
        } catch {
            try? server.stop()
            outcome.abortedReason = "seeding failed: \(error)"
            return outcome
        }
        outcome.metadata.corpusReducedTo = manifest.corpusReducedTo
        let info = server.serverMetadata()
        outcome.metadata.serverImage = info.image ?? outcome.metadata.serverImage
        outcome.metadata.serverImageDigest = info.digest ?? outcome.metadata.serverImageDigest
        outcome.metadata.serverConfiguration = info.configuration ?? outcome.metadata.serverConfiguration

        for round in 0..<rounds {
            for rate in cell.rates {
                for driver in Self.order(drivers, round: round) {
                    let step = "round \(round), rate \(Self.rateLabel(rate)), driver \(driver.name)"
                    let needed = Budget.stepRequiredBytes(cell, rate: rate)
                    let free: Int64
                    do { free = try server.freeDiskBytes() } catch {
                        outcome.abortedReason = "disk check before \(step) failed: \(error)"
                        return outcome
                    }
                    guard free >= needed else {
                        outcome.abortedReason = "disk: \(step) needs \(needed / 1_000_000) MB free, \(free / 1_000_000) MB are"
                        log("\(cell.id): stopped, \(outcome.abortedReason ?? "")")
                        return outcome
                    }
                    log("\(cell.id): \(step)")
                    do {
                        outcome.trials.append(try await runTrial(cell, manifest: manifest, round: round, rate: rate, driver: driver))
                    } catch {
                        // A server step (or the trial's own directory) failed: nothing after it can be trusted.
                        try? server.stop()
                        var record = TrialRecord(round: round, rate: rate, driver: driver.name)
                        record.error = error is ServerStepFailure ? "server: \(error)" : "\(error)"
                        outcome.trials.append(record)
                        outcome.abortedReason = "\(step): \(error)"
                        log("\(cell.id): stopped, \(outcome.abortedReason ?? "")")
                        return outcome
                    }
                }
            }
        }
        return outcome
    }

    // MARK: - Trial

    private struct ServerStepFailure: Error, CustomStringConvertible {
        var step: String
        var error: Error
        var description: String { "\(step) failed: \(error)" }
    }

    private func serverStep<T>(_ step: String, _ body: () async throws -> T) async throws -> T {
        do { return try await body() } catch { throw ServerStepFailure(step: step, error: error) }
    }

    private func runTrial(_ cell: Cell, manifest: SeedManifest, round: Int, rate: Double, driver: DriverSpec) async throws -> TrialRecord {
        let scenario = Self.scenario(cell: cell, manifest: manifest, rate: rate, round: round, driver: driver.name, phases: phases, category: category, seed: seed)
        let directory = workDirectory.appendingPathComponent("trials/r\(round)-\(Self.rateLabel(rate))-\(driver.name)")
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try await serverStep("restore snapshot") { try server.restoreSnapshot() }
        try await serverStep("drop caches") { try server.dropCaches() }
        try await serverStep("start server") { try await server.start() }
        try await serverStep("wait ready") { try await server.waitReady() }
        try await serverStep("wait for $by_category") { try await server.waitForByCategory(manifest) }
        if cell.kind == .persistentSubscription, let group = scenario.groupName {
            try await serverStep("create groups") { try await server.createGroups(category: scenario.category, group: group) }
        }

        var record = driver.isGhz
            ? await runGhz(scenario, driver: driver, directory: directory)
            : await runDriver(scenario, driver: driver, directory: directory)
        record.round = round

        if cell.kind == .persistentSubscription, let result = record.result, let group = scenario.groupName {
            do {
                record.serverAckedProgress = try await server.acknowledgedProgress(
                    category: scenario.category, group: group, expected: Int64(result.validation.expectedEvents)
                )
            } catch {
                log("acknowledged progress of \(group) unreadable: \(error)")
            }
        }
        do {
            try server.stop()
        } catch {
            // The next trial restores the data directory anyway; a failed restore then ends the cell.
            log("server stop after the trial: \(error)")
        }

        if let result = record.result {
            if record.error == nil { record.error = Self.hardFailure(result, scenario: scenario) }
            record.headroom?.eventsWritten = Self.eventsWritten(result, scenario: scenario)
        }
        return record
    }

    /// An in-process driver: `run --scenario … --connection … --out …`, killed after warmup + measure + drain +
    /// `killGraceSeconds` (+ the catch-up phase-1 bound). The monitor runs over the measure window; for catch-up,
    /// whose measure window starts after an unknown phase 1, from the end of warmup until the driver exits.
    private func runDriver(_ scenario: EffectiveScenario, driver: DriverSpec, directory: URL) async -> TrialRecord {
        var record = TrialRecord(round: 0, rate: scenario.rate, driver: driver.name)
        let scenarioFile = directory.appendingPathComponent("scenario.json")
        let out = directory.appendingPathComponent("out")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(scenario).write(to: scenarioFile)
        } catch {
            record.error = "cannot write the scenario: \(error)"
            return record
        }
        let command = Self.launchCommand(
            driver.command + ["run", "--scenario", scenarioFile.path, "--connection", server.connectionString, "--out", out.path],
            cpus: driverCPUs
        )
        let limit = Self.killAfterSeconds(scenario, grace: killGraceSeconds)
        let monitorUntilExit = scenario.kind == .catchUp
        let exit: DriverProcess.Exit
        (exit, record.headroom) = await monitored(
            warmup: scenario.warmupSeconds, measure: monitorUntilExit ? nil : scenario.measureSeconds,
            eventsWritten: Self.expectedEventsWritten(scenario)
        ) {
            await DriverProcess.run(command, logDirectory: directory, timeoutSeconds: limit)
        }
        if let problem = exit.problem(limit: limit, name: driver.name) {
            record.error = problem
            return record
        }
        do {
            let decoder = JSONDecoder()
            record.result = try decoder.decode(TrialResult.self, from: Data(contentsOf: out.appendingPathComponent("result.json")))
            record.histogram = try decoder.decode(HistogramFile.self, from: Data(contentsOf: out.appendingPathComponent("histogram.json")))
        } catch {
            record.result = nil
            record.error = "driver \(driver.name) exited 0 but its result is unreadable: \(error); stderr tail: \(exit.stderrTail)"
        }
        return record
    }

    /// ghz: a warmup run against the warmup streams, then the measured run with the monitor, each bounded by its
    /// duration + deadline + `killGraceSeconds`; the report is converted by `GhzAdapter` and also written as
    /// `out/result.json` and `out/histogram.json`.
    private func runGhz(_ scenario: EffectiveScenario, driver: DriverSpec, directory: URL) async -> TrialRecord {
        var record = TrialRecord(round: 0, rate: scenario.rate, driver: driver.name)
        let template = scenario.kind == .rebuild ? "read.json" : "append.json"
        let out = directory.appendingPathComponent("out")
        do {
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            let templateData = try Data(contentsOf: ghzConfigDirectory.appendingPathComponent(template))
            let runs: [(name: String, warmup: Bool, seconds: Double)] =
                (scenario.warmupSeconds > 0 ? [("warmup", true, scenario.warmupSeconds)] : []) + [("measure", false, scenario.measureSeconds)]
            for run in runs {
                let report = directory.appendingPathComponent("ghz-\(run.name).json")
                let config = directory.appendingPathComponent("ghz-\(run.name)-config.json")
                try GhzAdapter.callConfig(
                    template: templateData, templateDirectory: ghzConfigDirectory, scenario: scenario, warmup: run.warmup,
                    target: server.ghzTarget, seconds: run.seconds, output: report
                ).write(to: config)
                let command = Self.launchCommand(driver.command + ["--config", config.path], cpus: driverCPUs)
                let limit = run.seconds + Double(scenario.deadlineMillis) / 1000 + killGraceSeconds
                let logs = directory.appendingPathComponent("ghz-\(run.name)")
                try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
                let exit: DriverProcess.Exit
                if run.warmup {
                    exit = await DriverProcess.run(command, logDirectory: logs, timeoutSeconds: limit)
                } else {
                    (exit, record.headroom) = await monitored(warmup: 0, measure: run.seconds, eventsWritten: Self.expectedEventsWritten(scenario)) {
                        await DriverProcess.run(command, logDirectory: logs, timeoutSeconds: limit)
                    }
                }
                if let problem = exit.problem(limit: limit, name: "ghz (\(run.name))") {
                    record.error = problem
                    return record
                }
                if !run.warmup {
                    let (result, histogram) = try GhzAdapter.convert(report: Data(contentsOf: report), cellId: scenario.cellId, rate: scenario.rate)
                    record.result = result
                    record.histogram = histogram
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    try encoder.encode(result).write(to: out.appendingPathComponent("result.json"))
                    try encoder.encode(histogram).write(to: out.appendingPathComponent("histogram.json"))
                }
            }
        } catch {
            record.error = "ghz: \(error)"
        }
        return record
    }

    /// Runs `body` (the driver) while the monitor samples from `warmup` seconds after the start for `measure`
    /// seconds (nil: until `body` returns). A driver that ends before the window starts yields no sample.
    private func monitored<T: Sendable>(
        warmup: Double, measure: Double?, eventsWritten: Int64, _ body: @Sendable () async -> T
    ) async -> (T, HeadroomSample?) {
        let monitor = self.monitor
        let sampling = Task { () -> HeadroomSample? in
            do { try await Task.sleep(for: .seconds(warmup)) } catch { return nil }
            await monitor.start()
            if let measure {
                try? await Task.sleep(for: .seconds(measure))
            } else {
                while !Task.isCancelled { try? await Task.sleep(for: .seconds(3600)) }
            }
            return await monitor.stop(eventsWritten: eventsWritten)
        }
        let value = await body()
        sampling.cancel()
        return (value, await sampling.value)
    }

    // MARK: - Pure helpers

    /// Round `round`'s order: rotated so that it starts at driver `round mod n` (ABC, BCA, CAB, ...).
    static func order(_ drivers: [DriverSpec], round: Int) -> [DriverSpec] {
        guard !drivers.isEmpty else { return [] }
        let start = round % drivers.count
        return Array(drivers[start...] + drivers[..<start])
    }

    /// ghz is a transport reference for append and rebuild only (spec); subscription cells are Swift vs .NET.
    static func applicableDrivers(_ drivers: [DriverSpec], kind: ScenarioKind) -> [DriverSpec] {
        switch kind {
        case .appendLatency, .appendThroughput, .rebuild: drivers
        case .persistentSubscription, .catchUp: drivers.filter { !$0.isGhz }
        }
    }

    /// `taskset -c <cpus> <command…>` when `cpus` is set, else the command itself.
    static func launchCommand(_ command: [String], cpus: String?) -> [String] {
        guard let cpus else { return command }
        return ["taskset", "-c", cpus] + command
    }

    /// `250`, `1000`, `2.5`: for group and directory names.
    static func rateLabel(_ rate: Double) -> String {
        rate == rate.rounded() && abs(rate) < 1e15 ? "\(Int(rate))" : "\(rate)"
    }

    /// Driver kill bound: warmup + measure + drain + `grace`; a catch-up driver also gets its phase-1 bound
    /// (`max(120 s, catchUpExpectedEvents / 1000 s)`, driver contract), as phase 1 runs between warmup and measure.
    static func killAfterSeconds(_ scenario: EffectiveScenario, grace: Double) -> Double {
        var limit = scenario.warmupSeconds + scenario.measureSeconds + scenario.drainSeconds + grace
        if scenario.kind == .catchUp {
            limit += max(120, Double(scenario.catchUpExpectedEvents ?? 0) / 1000)
        }
        return limit
    }

    /// The trial's `EffectiveScenario` from the cell, the seed manifest and the fixed parameters (`Budget`).
    /// Naming per the driver contract: stream prefix == category (no `-`), warmup names add `w`, the persistent
    /// subscription group is `g<round>-<rate>-<driver>` (its warmup twin adds `w`).
    static func scenario(
        cell: Cell, manifest: SeedManifest, rate: Double, round: Int, driver: String, phases: TrialPhases, category: String, seed: UInt64
    ) -> EffectiveScenario {
        let streamCount = switch cell.kind {
        case .appendLatency, .appendThroughput: Budget.appendStreamCount
        case .rebuild: manifest.rebuildStreams.count
        case .persistentSubscription, .catchUp: Budget.subscriptionStreamCount
        }
        return EffectiveScenario(
            cellId: cell.id,
            kind: cell.kind,
            eventSize: cell.eventSize,
            metadataSize: Seeder().metadataSize,
            batchSize: cell.kind == .appendThroughput ? Budget.throughputBatchSize : 1,
            streamCount: streamCount,
            streamPrefix: category,
            category: category,
            groupName: cell.kind == .persistentSubscription ? "g\(round)-\(rateLabel(rate))-\(driver)" : nil,
            consumers: cell.kind == .persistentSubscription ? cell.consumers : nil,
            streamLength: cell.kind == .rebuild ? cell.streamLength : nil,
            rebuildStreams: cell.kind == .rebuild ? manifest.rebuildStreams : nil,
            catchUpExpectedEvents: cell.kind == .catchUp ? manifest.catchUpEvents : nil,
            rate: rate,
            warmupSeconds: phases.warmupSeconds,
            measureSeconds: phases.measureSeconds,
            drainSeconds: phases.drainSeconds,
            deadlineMillis: Budget.deadlineMillis,
            inFlightCap: Budget.inFlightCap,
            seed: seed
        )
    }

    /// The driver contract's hard failures, as a message; nil when the result stands. Live-write delivery
    /// shortfalls (persistent subscription, catch-up phase 2) and append counts are reported, not failures.
    static func hardFailure(_ result: TrialResult, scenario: EffectiveScenario) -> String? {
        var problems: [String] = []
        if result.cellId != scenario.cellId { problems.append("result is for cell \(result.cellId), not \(scenario.cellId)") }
        if result.targetRate != scenario.rate { problems.append("result is for rate \(result.targetRate), not \(scenario.rate)") }
        if result.succeeded + result.failed + result.dropped + result.timedOut != result.scheduled {
            problems.append("outcomes \(result.succeeded)+\(result.failed)+\(result.dropped)+\(result.timedOut) do not add up to \(result.scheduled) scheduled")
        }
        if !result.validation.payloadSizesOk {
            problems.append("payload sizes differ from \(scenario.eventSize) B data / \(scenario.metadataSize) B metadata")
        }
        switch scenario.kind {
        case .rebuild where result.timing == .scheduled && result.validation.receivedEvents != result.validation.expectedEvents:
            problems.append("rebuild read \(result.validation.receivedEvents) of \(result.validation.expectedEvents) seeded events")
        case .catchUp where result.catchUpSeconds == nil:
            problems.append("catch-up phase 1 shortfall: \(result.validation.receivedEvents) of \(result.validation.expectedEvents) corpus events arrived within the bound")
        default:
            break
        }
        return problems.isEmpty ? nil : problems.joined(separator: "; ")
    }

    /// Events written by the measure window as the monitor's buffered-growth allowance assumes before the result is
    /// known (rate × measure × events per operation; 0 for rebuild).
    static func expectedEventsWritten(_ scenario: EffectiveScenario) -> Int64 {
        guard scenario.kind != .rebuild else { return 0 }
        return Int64((scenario.rate * scenario.measureSeconds * Double(scenario.batchSize)).rounded())
    }

    /// Events the trial actually wrote in the measure window, from its result.
    static func eventsWritten(_ result: TrialResult, scenario: EffectiveScenario) -> Int64 {
        switch scenario.kind {
        case .rebuild: 0
        case .appendLatency, .appendThroughput: Int64(result.succeeded * scenario.batchSize)
        case .persistentSubscription: Int64(result.validation.expectedEvents)
        case .catchUp: Int64(max(0, result.validation.expectedEvents - (scenario.catchUpExpectedEvents ?? 0)))
        }
    }
}

// MARK: - Driver processes

enum DriverProcess {
    struct Exit: Sendable {
        var status: Int32
        /// True when the process ended by a signal (`status` is then the signal number).
        var signaled: Bool
        /// True when the runner had to kill it.
        var timedOut: Bool
        var stderrTail: String

        /// nil for a clean exit 0, else the trial's error message (exit status and stderr tail).
        func problem(limit: Double, name: String) -> String? {
            let how = signaled ? "signal \(status)" : "exit \(status)"
            if timedOut {
                return "driver \(name) did not exit within \(Int(limit)) s and was killed (\(how)); stderr tail: \(stderrTail)"
            }
            if signaled || status != 0 {
                return "driver \(name) failed with \(how); stderr tail: \(stderrTail)"
            }
            return nil
        }
    }

    /// Runs `command` (looked up on `PATH` through `/usr/bin/env`, which execs it, so the pid is the driver's) with
    /// stdout and stderr in `logDirectory/stdout.log` and `stderr.log`. After `timeoutSeconds` it sends SIGTERM, and
    /// SIGKILL 5 s later if needed. Never throws: a launch failure is an `Exit` with status -1.
    static func run(_ command: [String], logDirectory: URL, timeoutSeconds: Double) async -> Exit {
        let stdoutURL = logDirectory.appendingPathComponent("stdout.log")
        let stderrURL = logDirectory.appendingPathComponent("stderr.log")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        guard let stdout = try? FileHandle(forWritingTo: stdoutURL), let stderr = try? FileHandle(forWritingTo: stderrURL) else {
            return Exit(status: -1, signaled: false, timedOut: false, stderrTail: "cannot create log files in \(logDirectory.path)")
        }
        defer {
            try? stdout.close()
            try? stderr.close()
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = stderr
        let (exited, continuation) = AsyncStream<(Int32, Bool)>.makeStream()
        process.terminationHandler = { finished in
            continuation.yield((finished.terminationStatus, finished.terminationReason == .uncaughtSignal))
            continuation.finish()
        }
        do {
            try process.run()
        } catch {
            return Exit(status: -1, signaled: false, timedOut: false, stderrTail: "cannot launch \(command.joined(separator: " ")): \(error)")
        }
        let pid = process.processIdentifier
        let killed = Mutex(false)
        let killer = Task {
            guard (try? await Task.sleep(for: .seconds(timeoutSeconds))) != nil else { return }
            killed.withLock { $0 = true }
            kill(pid, SIGTERM)
            guard (try? await Task.sleep(for: .seconds(5))) != nil else { return }
            kill(pid, SIGKILL)
        }
        var status: (Int32, Bool) = (-1, false)
        for await value in exited {
            status = value
        }
        killer.cancel()
        withExtendedLifetime(process) {}
        return Exit(status: status.0, signaled: status.1, timedOut: killed.withLock { $0 }, stderrTail: tail(of: stderrURL))
    }

    /// The last 2,000 characters of a log file, trimmed.
    static func tail(of file: URL) -> String {
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        return String(text.suffix(2000)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
