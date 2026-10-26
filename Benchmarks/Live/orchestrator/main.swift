import ArgumentParser
import Foundation
import LiveBenchCore

/// Runs live benchmark cells. `trend` and `merge` come with the report (Task 11).
struct LiveOrchestratorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "LiveOrchestrator",
        abstract: "Orchestrates the live KurrentDB client benchmarks.",
        subcommands: [RunCell.self]
    )
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

    @Option(help: "JSON array of drivers: [{\"name\": \"swift\", \"command\": [...]}, ...]. Relative paths resolve against the working directory.")
    var drivers: String

    @Option(help: "Directory for cell-result.json and the trials' files.")
    var out: String

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

    func run() async throws {
        let allCells = try loadCells(from: URL(fileURLWithPath: cells))
        guard var cell = allCells.first(where: { $0.id == self.cell }) else {
            throw ValidationError("no cell '\(self.cell)' in \(cells); known: \(allCells.map(\.id).joined(separator: ", "))")
        }
        let specs = try JSONDecoder().decode([DriverSpec].self, from: Data(contentsOf: URL(fileURLWithPath: drivers)))
        struct ServerConfig: Decodable { var image: String }
        let image = try JSONDecoder().decode(ServerConfig.self, from: Data(contentsOf: URL(fileURLWithPath: serverConfig))).image

        var rounds = cell.rounds
        if smoke {
            cell.rates = Array(cell.rates.prefix(1))
            rounds = 1
        }
        let outDirectory = URL(fileURLWithPath: out)
        try FileManager.default.createDirectory(at: outDirectory, withIntermediateDirectories: true)
        let workDirectory = work.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("live-bench-\(cell.id)-\(UUID().uuidString.prefix(8))")

        let control = ServerControl(image: image, mode: cell.tls ? .tlsAuth : .plainAuth, cpuset: serverCpus, workDir: workDirectory)
        let server = CellServer(control: control)
        let monitor = Monitor(
            cores: serverCpus.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) },
            device: diskDevice(for: workDirectory) ?? "unknown",
            interval: .seconds(1),
            readProcStat: { try? String(contentsOfFile: "/proc/stat", encoding: .utf8) },
            readDiskStats: { try? String(contentsOfFile: "/proc/diskstats", encoding: .utf8) },
            readBuffered: { await server.byCategoryBuffered() }
        )

        var runner = TrialRunner(server: server, monitor: monitor, workDirectory: outDirectory)
        if smoke { runner.phases = .smoke }
        #if os(Linux)
        runner.driverCPUs = driverCpus.isEmpty ? nil : driverCpus
        #endif
        runner.metadata = clientMetadata(TrialRunner.applicableDrivers(specs, kind: cell.kind))

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

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let resultFile = outDirectory.appendingPathComponent("cell-result.json")
        try encoder.encode(result).write(to: resultFile)
        let failed = result.trials.filter { $0.error != nil }.count
        print("\(cell.id): \(result.trials.count) trials, \(failed) failed\(result.abortedReason.map { ", aborted: \($0)" } ?? ""); \(resultFile.path)")
    }
}

/// `Benchmarks/Live/config`, found from this source file (the orchestrator always runs from a source checkout).
private let configDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("config")

/// Client versions for `RunMetadata`: `<driver> version` of each in-process driver, `ghz --version`. A driver that
/// cannot report its version is left out (its trials will fail and say why).
private func clientMetadata(_ drivers: [DriverSpec]) -> RunMetadata {
    var metadata = RunMetadata()
    var clients: [DriverVersion] = []
    for driver in drivers {
        if driver.isGhz {
            // ghz prints its version on stderr.
            if let output = try? Shell.capture(driver.command[0], Array(driver.command.dropFirst()) + ["--version"]), output.status == 0 {
                metadata.ghzVersion = (output.stdout + output.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            continue
        }
        guard let output = try? Shell.run(driver.command[0], Array(driver.command.dropFirst()) + ["version"]),
              let version = try? JSONDecoder().decode(DriverVersion.self, from: Data(output.utf8))
        else {
            FileHandle.standardError.write(Data("[orchestrator] \(driver.name): `version` failed\n".utf8))
            continue
        }
        clients.append(version)
        switch version.client {
        case "swift":
            metadata.sdkCommit = version.clientVersion
            metadata.swiftToolchain = version.runtime
        case "dotnet":
            metadata.kurrentDBClientVersion = version.clientVersion
            metadata.dotnetRuntime = version.runtime
        default:
            break
        }
    }
    metadata.clients = clients
    return metadata
}

/// The block device under `directory` for the monitor's `/proc/diskstats` lookup (Linux): `df --output=source` gives
/// the partition, `/sys/class/block/<partition>/..` its disk (see `Budget`). nil elsewhere or when unknown.
private func diskDevice(for directory: URL) -> String? {
    #if os(Linux)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    guard let output = try? Shell.run("df", ["--output=source", directory.path]),
          let source = output.split(separator: "\n").last.map({ String($0).trimmingCharacters(in: .whitespaces) }),
          source.hasPrefix("/dev/")
    else { return nil }
    let partition = URL(fileURLWithPath: source).resolvingSymlinksInPath().lastPathComponent
    // `/sys/class/block/<name>` links into the device tree; a partition's parent there is its disk.
    let parent = URL(fileURLWithPath: "/sys/class/block/\(partition)").resolvingSymlinksInPath().deletingLastPathComponent().lastPathComponent
    let parentIsBlockDevice = !parent.isEmpty && FileManager.default.fileExists(atPath: "/sys/class/block/\(parent)")
    return parentIsBlockDevice ? parent : partition
    #else
    return nil
    #endif
}

// ArgumentParser's `main()` resolves to its synchronous entry point from top-level code (and then refuses to run an
// async command), so parse and dispatch here.
do {
    switch try LiveOrchestratorCommand.parseAsRoot() {
    case let command as RunCell:
        try await command.run()
    case var command:
        try command.run()
    }
} catch {
    LiveOrchestratorCommand.exit(withError: error)
}
