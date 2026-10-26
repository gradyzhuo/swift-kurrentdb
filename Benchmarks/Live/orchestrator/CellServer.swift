import Foundation
import KurrentDB
import LiveBenchCore
import Synchronization

/// The production `TrialServer`: one `ServerControl` container for a cell, the `Seeder`, and an SDK client to the
/// running server (recreated after every start) for the `$by_category` wait, the groups, acknowledged progress and
/// the monitor's projection backlog.
final class CellServer: TrialServer {
    let control: ServerControl
    private let state = Mutex<(client: KurrentDBClient?, digest: String?)>((nil, nil))

    init(control: ServerControl) {
        self.control = control
    }

    var connectionString: String { control.connectionString }

    /// Same credentials as `ServerControl.connectionString` (admin:changeit), as a gRPC `authorization` header.
    var ghzTarget: GhzTarget {
        GhzTarget(
            host: "127.0.0.1:\(control.port)",
            caFile: control.mode == .tlsAuth ? control.caFile : nil,
            authorization: "Basic " + Data("admin:changeit".utf8).base64EncodedString()
        )
    }

    func freeDiskBytes() throws -> Int64 {
        try FileManager.default.createDirectory(at: control.workDir, withIntermediateDirectories: true)
        let attributes = try FileManager.default.attributesOfFileSystem(forPath: control.workDir.path)
        guard let free = (attributes[.systemFreeSize] as? NSNumber)?.int64Value else {
            throw ServerError.dataDirectory("free space of \(control.workDir.path) unknown")
        }
        return free
    }

    func prepare(cell: Cell, corpusOverride: Int?) async throws -> SeedManifest {
        // The data directory is recreated for every cell.
        try cleanUp()
        if control.mode == .tlsAuth { try control.generateCertificates() }
        try await control.start()
        try await control.waitReady()
        var seeder = Seeder()
        seeder.catchUpCorpusOverride = corpusOverride
        let manifest = try await seeder.seed(cell: cell, client: currentClient())
        try stop()
        try control.snapshot()
        let digest = try? control.imageDigest()
        state.withLock { $0.digest = digest }
        return manifest
    }

    func restoreSnapshot() throws { try control.restoreSnapshot() }
    func dropCaches() throws { try control.dropCaches() }
    func start() async throws { try await control.start() }
    func waitReady() async throws { try await control.waitReady() }

    func waitForByCategory(_ manifest: SeedManifest) async throws {
        try await waitForSeedPosition(currentClient(), manifest)
    }

    func createGroups(category: String, group: String) async throws {
        let client = try currentClient()
        try await PersistentProgress.createGroup(client: client, stream: "$ce-\(category)", group: group)
        try await PersistentProgress.createGroup(client: client, stream: "$ce-\(category)w", group: group + "w")
    }

    func acknowledgedProgress(category: String, group: String, expected: Int64) async throws -> Int64 {
        try await PersistentProgress.read(
            client: currentClient(), stream: "$ce-\(category)", group: group, expected: expected, timeout: PersistentProgress.readTimeout
        )
    }

    func stop() throws {
        let client = state.withLock { s in
            defer { s.client = nil }
            return s.client
        }
        try? client?.shutdown()
        try control.stop()
    }

    func serverMetadata() -> (image: String?, digest: String?, configuration: [String: String]?) {
        (control.image, state.withLock { $0.digest }, control.effectiveConfiguration)
    }

    /// `$by_category`'s buffered events for the monitor; nil while no server answers.
    func byCategoryBuffered() async -> Int64? {
        guard let client = try? currentClient() else { return nil }
        return try? await withTimeout(.seconds(5)) { try await client.projections(system: .byCategory).detail()?.bufferedEvents }
    }

    /// Removes the data directory and the snapshot (between cells, and after the last one: they can be GBs).
    func cleanUp() throws {
        for directory in [control.dataDirectory, control.snapshotDirectory] where FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    private func currentClient() throws -> KurrentDBClient {
        if let client = state.withLock({ $0.client }) { return client }
        let client = KurrentDBClient(settings: try ClientSettings.parse(connectionString: control.connectionString))
        let winner = state.withLock { s in
            if let existing = s.client { return existing }
            s.client = client
            return client
        }
        if winner !== client { try? client.shutdown() }
        return winner
    }
}

/// File scope, so the protocol requirement `waitForByCategory(_:)` does not shadow the global function.
private func waitForSeedPosition(_ client: KurrentDBClient, _ manifest: SeedManifest) async throws {
    try await waitForByCategory(client: client, toReach: manifest.lastCommitPosition, prepare: manifest.lastPreparePosition, timeout: .seconds(120))
}
