import ArgumentParser
import Foundation
import KurrentDB
import LiveBenchCore

/// The Swift client under test. Implements `docs/driver-contract.md`: `run` executes one trial, `version` reports
/// which SDK commit is measured.
struct LiveDriverSwift: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "LiveDriverSwift",
        abstract: "swift-kurrentdb driver for the live benchmarks.",
        subcommands: [Run.self, Version.self]
    )
}

struct Run: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Run one trial (warmup, measure, drain) of one rate step.")

    @Option(help: "EffectiveScenario JSON file.")
    var scenario: String

    @Option(help: "KurrentDB connection string, used with the client's default settings.")
    var connection: String

    @Option(help: "Directory for result.json and histogram.json (created if missing).")
    var out: String

    func run() async throws {
        let scenario = try JSONDecoder().decode(EffectiveScenario.self, from: Data(contentsOf: URL(fileURLWithPath: scenario)))
        try scenario.validate()
        let outDirectory = URL(fileURLWithPath: out)
        try FileManager.default.createDirectory(at: outDirectory, withIntermediateDirectories: true)

        let client = KurrentDBClient(settings: try ClientSettings.parse(connectionString: connection))
        defer { try? client.shutdown() }

        log("\(scenario.cellId): \(scenario.kind.rawValue) at \(scenario.rate)/s, warmup \(scenario.warmupSeconds) s, measure \(scenario.measureSeconds) s")
        let trial: Trial = switch scenario.kind {
        case .appendLatency, .appendThroughput:
            await runAppend(scenario, client: client)
        case .rebuild:
            await runRebuild(scenario, client: client)
        case .persistentSubscription:
            try await runPersistentSubscription(scenario, client: client)
        case .catchUp:
            try await runCatchUp(scenario, client: client)
        }

        let result = trial.result(for: scenario)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(result).write(to: outDirectory.appendingPathComponent("result.json"))
        try encoder.encode(HistogramFile(trial.recorder.histogram)).write(to: outDirectory.appendingPathComponent("histogram.json"))
        log("done: \(result.succeeded)/\(result.scheduled) succeeded, \(result.failed) failed, \(result.dropped) dropped, \(result.timedOut) timed out")
    }
}

struct Version: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Print the driver version as JSON.")

    func run() throws {
        let version = DriverVersion(client: "swift", clientVersion: try sdkCommit(), runtime: swiftRuntime)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        print(String(decoding: try encoder.encode(version), as: UTF8.self))
    }

    /// Env `LIVE_BENCH_SDK_COMMIT`, else `git rev-parse HEAD` of the repository holding this source file (the driver
    /// consumes the SDK by path from the same repository).
    private func sdkCommit() throws -> String {
        if let commit = ProcessInfo.processInfo.environment["LIVE_BENCH_SDK_COMMIT"], !commit.isEmpty { return commit }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", URL(fileURLWithPath: #filePath).deletingLastPathComponent().path, "rev-parse", "HEAD"]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let commit = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0, !commit.isEmpty else {
            throw ValidationError("cannot determine the SDK commit: set LIVE_BENCH_SDK_COMMIT")
        }
        return commit
    }

    private var swiftRuntime: String {
        #if swift(>=6.5)
        "swift 6.5+"
        #elseif swift(>=6.4)
        "swift 6.4"
        #elseif swift(>=6.3)
        "swift 6.3"
        #elseif swift(>=6.2)
        "swift 6.2"
        #elseif swift(>=6.1)
        "swift 6.1"
        #else
        "swift 6.0"
        #endif
    }
}

extension EffectiveScenario {
    /// Rejects scenarios the driver cannot run as the contract describes (exit non-zero before connecting).
    func validate() throws {
        guard rate.isFinite, rate > 0 else { throw ValidationError("rate must be positive") }
        guard streamCount > 0, batchSize > 0, inFlightCap >= 0, deadlineMillis > 0 else {
            throw ValidationError("streamCount, batchSize and deadlineMillis must be positive, inFlightCap not negative")
        }
        switch kind {
        case .appendLatency, .appendThroughput:
            break
        case .rebuild:
            guard let streams = rebuildStreams, !streams.isEmpty, streamLength != nil else {
                throw ValidationError("rebuild needs rebuildStreams and streamLength")
            }
        case .persistentSubscription:
            guard groupName != nil else { throw ValidationError("persistentSubscription needs groupName") }
            guard batchSize == 1 else { throw ValidationError("subscription kinds append one event per operation") }
        case .catchUp:
            guard catchUpExpectedEvents != nil else { throw ValidationError("catchUp needs catchUpExpectedEvents") }
            guard batchSize == 1 else { throw ValidationError("subscription kinds append one event per operation") }
        }
    }
}

/// Progress on stdout, written unbuffered (one write per line) so a killed driver's log is complete. The orchestrator
/// reads only the output files and the stderr tail.
func log(_ message: String) {
    FileHandle.standardOutput.write(Data("[LiveDriverSwift] \(message)\n".utf8))
}

// ArgumentParser's `main()` resolves to its synchronous entry point from top-level code (and then refuses to run an
// async command), so parse and dispatch to the concrete commands here.
do {
    switch try LiveDriverSwift.parseAsRoot() {
    case let command as Run:
        try await command.run()
    case var command:
        try command.run()
    }
} catch {
    LiveDriverSwift.exit(withError: error)
}
