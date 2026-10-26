import Foundation
import KurrentDB
import LiveBenchCore
import Synchronization

/// The client whose driver a test runs. Only the launch command differs between them; preparation is shared.
enum Client: CustomStringConvertible, Sendable {
    case swift, dotnet

    var description: String {
        switch self {
        case .swift: "swift"
        case .dotnet: "dotnet"
        }
    }

    /// The driver's command line before its own arguments: an executable and the arguments that select the driver.
    /// `LIVE_BENCH_SWIFT_DRIVER` overrides the Swift driver's location (e.g. another scratch path). The .NET driver runs
    /// as `dotnet <dll>`; it is built (`dotnet build -c Release`) once per test process, so a stale build is never run.
    var driverCommand: (executable: URL, arguments: [String]) {
        get throws {
            switch self {
            case .swift:
                if let path = ProcessInfo.processInfo.environment["LIVE_BENCH_SWIFT_DRIVER"] {
                    return (URL(fileURLWithPath: path), [])
                }
                // `swift test` builds every product of the package, the driver included.
                let built = livePackageDirectory.appendingPathComponent(".build/debug/LiveDriverSwift")
                guard FileManager.default.isExecutableFile(atPath: built.path) else {
                    throw HarnessError("\(built.path) is missing: run `swift build --product LiveDriverSwift` first")
                }
                return (built, [])
            case .dotnet:
                let dll = try DotNetDriverBuild.dll()
                return (URL(fileURLWithPath: "/usr/bin/env"), ["dotnet", dll.path])
            }
        }
    }
}

/// Builds the .NET driver in Release once per test process (`dotnet` from `PATH`).
enum DotNetDriverBuild {
    static let projectDirectory = livePackageDirectory.appendingPathComponent("drivers/dotnet")
    static let dllPath = projectDirectory.appendingPathComponent("bin/Release/net8.0/LiveDriver.DotNet.dll")
    private static let built = Mutex<Result<URL, HarnessError>?>(nil)

    static func dll() throws -> URL {
        try built.withLock { state in
            if state == nil {
                do {
                    try runTool("dotnet", ["build", projectDirectory.path, "-c", "Release", "-nologo", "-v", "q"])
                    state = .success(dllPath)
                } catch {
                    state = .failure(HarnessError("dotnet build of the .NET driver failed: \(error)"))
                }
            }
            return try state!.get()
        }
    }
}

/// What one driver run produced.
struct DriverRun {
    var result: TrialResult
    var histogram: HistogramFile
    /// The scenario as the driver received it (unique names per run).
    var scenario: EffectiveScenario
    /// The last few KB of the driver's stdout, for failure messages.
    var log: String
    /// The driver's whole stderr (the measure-start marker, plus logs of a driver that logs there).
    var stderr: String
}

/// Runs one trial of `client`'s driver against `LiveServer.current` and returns its `result.json`.
func runDriver(_ client: Client, scenario: EffectiveScenario) async throws -> TrialResult {
    try await runDriverDetailed(client, scenario: scenario).result
}

/// Prepares the server for `scenario` the way the orchestrator will (seeding, groups, `$by_category`), runs the driver
/// on a copy of `scenario` with names unique to this run, and decodes both output files.
func runDriverDetailed(_ client: Client, scenario: EffectiveScenario) async throws -> DriverRun {
    guard let server = LiveServer.current else {
        throw HarnessError("no LiveServer: add the `.liveServer` trait to the suite and set LIVE_BENCH_DOCKER=1")
    }
    let scenario = isolated(scenario)
    try await prepare(scenario, connectionString: server.connectionString)

    let workDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("live-driver-\(UUID().uuidString)")
    let outDirectory = workDirectory.appendingPathComponent("out")
    try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: workDirectory) }
    let scenarioFile = workDirectory.appendingPathComponent("scenario.json")
    try JSONEncoder().encode(scenario).write(to: scenarioFile)

    let limit = scenario.warmupSeconds + scenario.measureSeconds + scenario.drainSeconds + 180
    let command = try client.driverCommand
    let (status, stderr) = try await launch(
        command.executable,
        command.arguments + ["run", "--scenario", scenarioFile.path, "--connection", server.connectionString, "--out", outDirectory.path],
        logDirectory: workDirectory,
        timeout: .seconds(limit)
    )
    guard status == 0 else {
        throw HarnessError("driver exited \(status): \(stderr.suffix(2000))")
    }
    let decoder = JSONDecoder()
    return DriverRun(
        result: try decoder.decode(TrialResult.self, from: Data(contentsOf: outDirectory.appendingPathComponent("result.json"))),
        histogram: try decoder.decode(HistogramFile.self, from: Data(contentsOf: outDirectory.appendingPathComponent("histogram.json"))),
        scenario: scenario,
        log: String(((try? String(contentsOf: workDirectory.appendingPathComponent("stdout.log"), encoding: .utf8)) ?? "").suffix(4000)),
        stderr: stderr
    )
}

/// `<driver> version`, decoded.
func driverVersion(_ client: Client) async throws -> DriverVersion {
    let workDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("live-driver-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: workDirectory) }
    let command = try client.driverCommand
    let (status, stderr) = try await launch(command.executable, command.arguments + ["version"], logDirectory: workDirectory, timeout: .seconds(60))
    guard status == 0 else { throw HarnessError("version exited \(status): \(stderr)") }
    return try JSONDecoder().decode(DriverVersion.self, from: Data(contentsOf: workDirectory.appendingPathComponent("stdout.log")))
}

// MARK: - Unique names

/// Gives the run its own streams, category and group so runs sharing one server never see each other's events.
/// The prefix equals the category and contains no `-`: `$by_category` takes everything before the first `-` of a
/// stream name as its category, so `<prefix>-<n>` lands in `$ce-<prefix>` and `<prefix>w-<n>` in `$ce-<prefix>w`.
private func isolated(_ scenario: EffectiveScenario) -> EffectiveScenario {
    var s = scenario
    let token = "b" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased()
    s.streamPrefix = token
    s.category = token
    if s.groupName != nil { s.groupName = "\(token)-group" }
    if let streams = s.rebuildStreams { s.rebuildStreams = streams.indices.map { "\(token)-\($0)" } }
    return s
}

// MARK: - Preparation (what the orchestrator does before `run`)

private func prepare(_ s: EffectiveScenario, connectionString: String) async throws {
    let client = KurrentDBClient(settings: try ClientSettings.parse(connectionString: connectionString))
    defer { try? client.shutdown() }
    let factory = PayloadFactory(dataSize: s.eventSize, metadataSize: s.metadataSize, seed: s.seed)

    switch s.kind {
    case .appendLatency, .appendThroughput:
        break

    case .rebuild:
        guard let streams = s.rebuildStreams, let length = s.streamLength else {
            throw HarnessError("rebuild needs rebuildStreams and streamLength")
        }
        // Measured streams as named, warmup streams `<prefix>w-<n>` of the same shape.
        let warmup = streams.indices.map { "\(s.streamPrefix)w-\($0)" }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (n, name) in (streams + warmup).enumerated() {
                let index = n % streams.count
                group.addTask {
                    let events = (0..<length).map { benchEvent(factory, index: index * length + $0) }
                    try await client.streams(specified: name).append(events: events)
                }
            }
            try await group.waitForAll()
        }

    case .persistentSubscription:
        guard let groupName = s.groupName else { throw HarnessError("persistentSubscription needs groupName") }
        try await enableByCategory(client)
        for (stream, group) in [("$ce-\(s.category)", groupName), ("$ce-\(s.category)w", groupName + "w")] {
            try await client.persistentSubscriptions(stream: stream, group: group).create {
                $0.settings.resolveLink = true
                $0.settings.consumerStrategy = .roundRobin
                $0.revision = .start
            }
        }

    case .catchUp:
        guard let corpus = s.catchUpExpectedEvents else { throw HarnessError("catchUp needs catchUpExpectedEvents") }
        try await enableByCategory(client)
        // Corpus event k goes to `<prefix>-<k % streamCount>`, appended per stream in batches.
        let streamCount = min(s.streamCount, corpus)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for n in 0..<streamCount {
                group.addTask {
                    let indices = Array(stride(from: n, to: corpus, by: streamCount))
                    for chunk in stride(from: 0, to: indices.count, by: 500) {
                        let events = indices[chunk..<min(chunk + 500, indices.count)].map { benchEvent(factory, index: $0) }
                        try await client.streams(specified: "\(s.streamPrefix)-\(n)").append(events: events)
                    }
                }
            }
            try await group.waitForAll()
        }
        try await waitForCategory(client, category: s.category, count: corpus, timeout: .seconds(120))
    }
}

private func benchEvent(_ factory: PayloadFactory, index: Int) -> EventData {
    EventData(eventType: "BenchEvent", data: factory.data(index: index), contentType: .json, customMetadata: factory.metadata(index: index))
}

/// Enables `$by_category`, retrying while the projection subsystem is still starting (a request sent that early can
/// stay unanswered, so each attempt is bounded).
private func enableByCategory(_ client: KurrentDBClient) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(120))
    while true {
        do {
            try await withTimeout(.seconds(5)) { try await client.projections(system: .byCategory).enable() }
            return
        } catch {
            if clock.now >= deadline { throw error }
            try await Task.sleep(for: .milliseconds(500))
        }
    }
}

/// Waits until `$ce-<category>` holds `count` link events (its last event revision is `count - 1`).
private func waitForCategory(_ client: KurrentDBClient, category: String, count: Int, timeout: Duration) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    var last: UInt64?
    while clock.now < deadline {
        last = try? await withTimeout(.seconds(5)) {
            try await client.streams(specified: "$ce-\(category)").read {
                $0.direction = .backward
                $0.revision = .end
                $0.limit = 1
            }.lazy.first(where: { _ in true }).map { try $0.event.record.revision }
        }
        if let last, last + 1 >= UInt64(count) { return }
        try await Task.sleep(for: .milliseconds(200))
    }
    throw HarnessError("$ce-\(category) holds \(last.map { $0 + 1 } ?? 0) of \(count) events after \(timeout)")
}

/// Runs `operation`, throwing if it has not finished after `limit` (it is then cancelled and abandoned: an RPC that
/// ignores cancellation cannot hold the caller, unlike a task group child).
private func withTimeout<T: Sendable>(_ limit: Duration, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        let once = ResumeOnce(continuation)
        let work = Task {
            do { once.resume(.success(try await operation())) } catch { once.resume(.failure(error)) }
        }
        Task {
            try? await Task.sleep(for: limit)
            work.cancel()
            once.resume(.failure(HarnessError("timed out after \(limit)")))
        }
    }
}

private final class ResumeOnce<T: Sendable>: Sendable {
    private let continuation: Mutex<CheckedContinuation<T, Error>?>

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = Mutex(continuation)
    }

    func resume(_ result: Result<T, Error>) {
        continuation.withLock { $0.take() }?.resume(with: result)
    }
}

// MARK: - Process

/// Runs `executable` with stdout/stderr in files (a chatty child cannot block on a full pipe) and returns its exit
/// status and stderr. Kills it after `timeout`.
private func launch(_ executable: URL, _ arguments: [String], logDirectory: URL, timeout: Duration) async throws -> (Int32, String) {
    let stdoutURL = logDirectory.appendingPathComponent("stdout.log")
    let stderrURL = logDirectory.appendingPathComponent("stderr.log")
    FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
    FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.standardOutput = try FileHandle(forWritingTo: stdoutURL)
    process.standardError = try FileHandle(forWritingTo: stderrURL)

    let status: Int32 = try await withThrowingTaskGroup(of: Int32?.self) { group in
        let exited = AsyncStream<Int32> { continuation in
            process.terminationHandler = { continuation.yield($0.terminationStatus); continuation.finish() }
        }
        try process.run()
        group.addTask { await exited.first(where: { _ in true }) ?? -1 }
        group.addTask {
            try await Task.sleep(for: timeout)
            return nil
        }
        let first = try await group.next() ?? nil
        group.cancelAll()
        guard let first else {
            process.terminate()
            throw HarnessError("\(executable.lastPathComponent) did not finish within \(timeout)")
        }
        return first
    }
    let stderr = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""
    return (status, stderr)
}
