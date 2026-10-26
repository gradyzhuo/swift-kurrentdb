import ArgumentParser
import Foundation
import LiveBenchCore

/// Runs live benchmark cells (`run-cell`), assembles their results bundle and report (`merge`), and runs the nightly
/// Swift-only trend (`trend`).
struct LiveOrchestratorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "LiveOrchestrator",
        abstract: "Orchestrates the live KurrentDB client benchmarks.",
        subcommands: [RunCell.self, Merge.Command.self, Trend.self]
    )
}

/// Server and pinning options shared by `run-cell` and `trend`.
struct CellOptions: ParsableArguments {
    @Option(help: "JSON array of drivers: [{\"name\": \"swift\", \"command\": [...]}, ...]. Relative paths resolve against the working directory.")
    var drivers: String

    @Option(help: "Server work directory (certificates, data, snapshot, logs). Data and snapshot are removed at the end; the default, a temporary directory, entirely.")
    var work: String?

    @Option(help: "Cells file.")
    var cells: String = configDirectory.appendingPathComponent("cells.json").path

    @Option(help: "Server config file ({\"image\": ...}).")
    var serverConfig: String = configDirectory.appendingPathComponent("server.json").path

    @Option(help: "CPUs the server container is pinned to.")
    var serverCpus = "0,1"

    @Option(help: "CPUs each driver is pinned to with taskset (Linux only; empty for none).")
    var driverCpus = "2,3"

    @Flag(help: "Smoke run: 1 round, the first rate only, 5 s warmup and 5 s measure. Never a published result.")
    var smoke = false

    func loadCells() throws -> [Cell] { try LiveBenchCore.loadCells(from: URL(fileURLWithPath: cells)) }

    func loadDrivers() throws -> [DriverSpec] {
        try JSONDecoder().decode([DriverSpec].self, from: Data(contentsOf: URL(fileURLWithPath: drivers)))
    }

    /// Runs `cell` (its rates as given) with `specs` over `rounds` and writes `<out>/cell-result.json` after every
    /// trial and at the end. The environment's metadata (`RunMetadata.collect`) fills what the drivers did not report.
    func run(_ cell: Cell, specs: [DriverSpec], rounds: Int, out outDirectory: URL) async throws -> CellResult {
        struct ServerConfig: Decodable { var image: String }
        let image = try JSONDecoder().decode(ServerConfig.self, from: Data(contentsOf: URL(fileURLWithPath: serverConfig))).image
        try FileManager.default.createDirectory(at: outDirectory, withIntermediateDirectories: true)
        let workDirectory = work.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("live-bench-\(cell.id)-\(UUID().uuidString.prefix(8))")

        let control = ServerControl(image: image, mode: cell.tls ? .tlsAuth : .plainAuth, cpuset: serverCpus, workDir: workDirectory)
        let server = CellServer(control: control)
        let device = DiskDevice.holding(workDirectory)
        let streamPrefix = Seeder().category + "-"
        let monitor = Monitor(
            cores: serverCpus.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) },
            device: device ?? "unknown",
            interval: .seconds(1),
            readProcStat: { try? String(contentsOfFile: "/proc/stat", encoding: .utf8) },
            readDiskStats: { try? String(contentsOfFile: "/proc/diskstats", encoding: .utf8) },
            readBuffered: { await server.byCategoryBuffered() },
            readProjectionCatchUp: { await server.byCategoryCatchUp(streamPrefix: streamPrefix, within: $0) }
        )
        #if os(Linux)
        // CI measures headroom from /proc; without it no step would get a comparison, so stop before any work.
        guard let device else {
            throw ValidationError("cannot resolve the block device of \(workDirectory.path) in /proc/diskstats (by its device number); server headroom could not be measured")
        }
        do { try await monitor.checkReadable() } catch {
            throw ValidationError("server headroom cannot be measured (device \(device), server CPUs \(serverCpus)): \(error)")
        }
        #endif

        var runner = TrialRunner(server: server, monitor: monitor, workDirectory: outDirectory)
        runner.jobStarted = jobStartDate()
        if smoke { runner.phases = .smoke }
        #if os(Linux)
        runner.driverCPUs = driverCpus.isEmpty ? nil : driverCpus
        #endif
        runner.metadata = clientMetadata(TrialRunner.applicableDrivers(specs, kind: cell.kind))
            .filling(from: RunMetadata.collect(environment: ProcessInfo.processInfo.environment))
        let resultFile = outDirectory.appendingPathComponent("cell-result.json")
        // Rewritten after every trial (atomic replace), so a killed job keeps the trials done so far.
        runner.onProgress = { partial in
            do { try writeCellResult(partial, to: resultFile) } catch {
                FileHandle.standardError.write(Data("[orchestrator] cannot write \(resultFile.path): \(error)\n".utf8))
            }
        }

        let result: CellResult
        do {
            result = try await runner.runCell(cell, drivers: specs, rounds: rounds)
        } catch {
            try? server.stop()
            try? server.cleanUp()
            throw error
        }
        try? server.stop()
        try? server.cleanUp()
        if work == nil { try? FileManager.default.removeItem(at: workDirectory) }

        try writeCellResult(result, to: resultFile)
        let failed = result.trials.filter { $0.error != nil }.count
        print("\(cell.id): \(result.trials.count) trials, \(failed) failed\(result.abortedReason.map { ", aborted: \($0)" } ?? ""); \(resultFile.path)")
        return result
    }
}

/// `run-cell`: seeds one cell, runs every rate step for every client over the rounds (rotated), and writes
/// `<out>/cell-result.json` plus each trial's files under `<out>/trials/`.
struct RunCell: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run-cell",
        abstract: "Run one cell (scenario x event size) with every client, interleaved over rounds."
    )

    @Option(help: "Cell id from the cells file.")
    var cell: String

    @Option(help: "Directory for cell-result.json and the trials' files.")
    var out: String

    @OptionGroup var options: CellOptions

    func run() async throws {
        let allCells = try options.loadCells()
        guard var cell = allCells.first(where: { $0.id == self.cell }) else {
            throw ValidationError("no cell '\(self.cell)' in \(options.cells); known: \(allCells.map(\.id).joined(separator: ", "))")
        }
        let specs = try options.loadDrivers()
        var rounds = cell.rounds
        if options.smoke {
            cell.rates = Array(cell.rates.prefix(1))
            rounds = 1
        }
        _ = try await options.run(cell, specs: specs, rounds: rounds, out: URL(fileURLWithPath: out))
    }
}

extension Merge {
    /// `merge`: the results bundle and report from the cells' outputs.
    struct Command: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "merge",
            abstract: "Assemble the results bundle (<out>/<YYYY-MM-DD>-<server version>/) and report.html from cell results."
        )

        @Option(help: "Directory holding the cells' outputs (each cell-result.json next to its trials/), at any depth.")
        var `in`: String

        @Option(help: "Results directory; the bundle is created inside it.")
        var out: String

        func run() throws {
            let bundle = try Merge.bundle(from: URL(fileURLWithPath: `in`), into: URL(fileURLWithPath: out))
            print(bundle.appendingPathComponent("report.html").path)
        }
    }
}

/// `trend`: every headline cell at one fixed moderate rate (`BMF.trendRate`), Swift only, one round; writes each
/// cell's result under `<out>/<cell id>/` and the Bencher file `<out>/bmf.json`. Fails when no benchmark was produced.
struct Trend: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "trend",
        abstract: "Nightly Swift-only trend: one moderate rate per headline cell, one round, Bencher output."
    )

    @Option(help: "Directory for bmf.json and each cell's results.")
    var out: String

    @Option(help: "Comma-separated cell ids (default: every headline cell).")
    var only: String?

    @OptionGroup var options: CellOptions

    func run() async throws {
        let wanted = only.map { Set($0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }) }
        let cells = try options.loadCells().filter { wanted?.contains($0.id) ?? ($0.tier == .headline) }
        guard !cells.isEmpty else { throw ValidationError("no cells selected") }
        let specs = try options.loadDrivers().filter { $0.name == CellAnalysis.swift }
        guard !specs.isEmpty else { throw ValidationError("the drivers file has no \"swift\" driver") }

        let outDirectory = URL(fileURLWithPath: out)
        var results: [CellResult] = []
        for var cell in cells {
            cell.rates = [BMF.trendRate(for: cell)]
            cell.rounds = 1
            results.append(try await options.run(cell, specs: specs, rounds: 1, out: outDirectory.appendingPathComponent(cell.id)))
        }
        let bmf = BMF.trend(results)
        let file = outDirectory.appendingPathComponent("bmf.json")
        try bmf.write(to: file)
        let count = (try? JSONSerialization.jsonObject(with: bmf) as? [String: Any])?.count ?? 0
        print("\(count) benchmarks; \(file.path)")
        guard count > 0 else { throw ValidationError("no trend benchmark produced (every trial failed)") }
    }
}

/// Writes `result` as pretty JSON, replacing `file` atomically (a reader never sees a half-written file).
func writeCellResult(_ result: CellResult, to file: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(result).write(to: file, options: .atomic)
}

/// `Benchmarks/Live/config`, found from this source file (the orchestrator always runs from a source checkout).
private let configDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("config")

/// Client versions for `RunMetadata`: `<driver> version` of each in-process driver, `ghz --version`. A driver that
/// cannot report its version is left out (its trials will fail and say why).
private func clientMetadata(_ drivers: [DriverSpec]) -> RunMetadata {
    var versions: [DriverVersion] = []
    var ghzVersion: String?
    for driver in drivers {
        if driver.isGhz {
            // ghz prints its version on stderr.
            if let output = try? Shell.capture(driver.command[0], Array(driver.command.dropFirst()) + ["--version"]), output.status == 0 {
                ghzVersion = (output.stdout + output.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            continue
        }
        guard let output = try? Shell.run(driver.command[0], Array(driver.command.dropFirst()) + ["version"]),
              let version = try? JSONDecoder().decode(DriverVersion.self, from: Data(output.utf8))
        else {
            FileHandle.standardError.write(Data("[orchestrator] \(driver.name): `version` failed\n".utf8))
            continue
        }
        versions.append(version)
    }
    var metadata = RunMetadata.fromDrivers(versions)
    metadata.ghzVersion = ghzVersion
    return metadata
}

/// When the CI job started: env `LIVE_BENCH_JOB_STARTED` (Unix seconds, set by the workflow's first step), else now.
private func jobStartDate() -> Date {
    ProcessInfo.processInfo.environment["LIVE_BENCH_JOB_STARTED"].flatMap(TimeInterval.init).map(Date.init(timeIntervalSince1970:)) ?? Date()
}

// ArgumentParser's `main()` resolves to its synchronous entry point from top-level code (and then refuses to run an
// async command), so parse and dispatch here.
do {
    switch try LiveOrchestratorCommand.parseAsRoot() {
    case let command as RunCell:
        try await command.run()
    case let command as Trend:
        try await command.run()
    case var command:
        try command.run()
    }
} catch {
    LiveOrchestratorCommand.exit(withError: error)
}
