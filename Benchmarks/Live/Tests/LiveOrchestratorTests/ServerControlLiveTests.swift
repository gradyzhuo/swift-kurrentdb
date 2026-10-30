import Foundation
import KurrentDB
@testable import LiveBenchCore
@testable import LiveOrchestrator
import Testing

/// `ServerControl` and `Seeder` against real, throwaway KurrentDB containers (image from `config/server.json`), each in
/// its own temporary work directory. Run with `LIVE_BENCH_DOCKER=1`.
@Suite("Server control (live)", .serialized)
struct ServerControlLiveTests {
    @Test(.enabled(if: docker))
    func plainAuthKeepsAuthenticationOn() async throws {
        try await withServer(.plainAuth) { server in
            #expect(server.connectionString.contains("tls=false"))
            let admin = try client(server.connectionString)
            defer { try? admin.shutdown() }
            _ = try await admin.streams(specified: "auth-probe").append(events: [.fixture])

            let anonymous = try client(server.connectionString.replacingOccurrences(of: "admin:changeit@", with: ""))
            defer { try? anonymous.shutdown() }
            // The same server accepted the admin's append, so the rejection is authentication, not connectivity.
            let error = await #expect(throws: KurrentError.self) {
                _ = try await anonymous.streams(specified: "auth-probe").append(events: [.fixture])
            }
            if let error, case .accessDenied = error {} else {
                Issue.record("expected accessDenied, got \(String(describing: error))")
            }
        }
    }

    @Test(.enabled(if: docker))
    func restoreBringsBackSeededStateExactly() async throws {
        try await withServer(.tlsAuth) { server in
            #expect(server.connectionString.contains("tls=true"))
            var seeder = Seeder()
            seeder.rebuildStreamCount = 1
            let manifest = try await withClient(server) { client in
                try await seeder.seed(cell: .fixture(kind: .rebuild, streamLength: 10), client: client)
            }
            #expect(manifest.rebuildStreams == ["bench-0"])
            #expect(manifest.lastCommitPosition > 0 && manifest.lastPreparePosition > 0)
            try server.stop()
            try server.snapshot()

            try await server.start()
            try await server.waitReady()
            try await withClient(server) { client in
                #expect(try await count(client, "bench-0") == 10)
                _ = try await client.streams(specified: "bench-0").append(events: Array(repeating: .fixture, count: 5))
                #expect(try await count(client, "bench-0") == 15)
            }
            try server.stop()
            // Junk the restore must remove (a stale file and directory left in the data directory).
            let junk = server.dataDirectory.appendingPathComponent("junk")
            try FileManager.default.createDirectory(at: junk, withIntermediateDirectories: true)
            try Data("stale".utf8).write(to: junk.appendingPathComponent("stale.chk"))
            try server.restoreSnapshot()
            #expect(!FileManager.default.fileExists(atPath: junk.path))
            #expect(!FileManager.default.fileExists(atPath: server.dataDirectory.appendingPathComponent("snapshot").path))
            #expect(try directoryListing(server.dataDirectory) == directoryListing(server.snapshotDirectory))
            try server.dropCaches()

            try await server.start()
            try await server.waitReady()
            try await withClient(server) { client in
                try await waitForByCategory(
                    client: client, toReach: manifest.lastCommitPosition, prepare: manifest.lastPreparePosition, timeout: .seconds(120)
                )
                #expect(try await count(client, "bench-0") == 10)
                #expect(try await count(client, "benchw-0") == 10)
            }
        }
    }

    @Test(.enabled(if: docker))
    func catchUpCorpusFillsTheCategoryExactly() async throws {
        try await withServer(.plainAuth) { server in
            var seeder = Seeder()
            seeder.catchUpCorpusOverride = 300
            seeder.catchUpStreamCount = 7
            let manifest = try await withClient(server) { client in
                let manifest = try await seeder.seed(cell: .fixture(kind: .catchUp), client: client)
                // seed() waits for `$by_category`, so the category is complete when it returns.
                #expect(try await count(client, "$ce-bench") == 300)
                #expect(try await count(client, "$ce-benchw") == 0)
                return manifest
            }
            #expect(manifest.catchUpCategory == "bench")
            #expect(manifest.catchUpEvents == 300)
            #expect(manifest.corpusReducedTo == 300)
            #expect(manifest.rebuildStreams.isEmpty)
            #expect(try server.imageDigest().hasPrefix("sha256:"))
        }
    }

    @Test(.enabled(if: docker))
    func notReadyServerFailsWithinTimeout() async throws {
        let workDir = try temporaryWorkDir()
        defer { removeWorkDir(workDir) }
        var server = ServerControl(image: try serverImage(), mode: .plainAuth, workDir: workDir)
        server.port = try freeLocalPort()
        server.extraEnvironment = ["KURRENTDB_NODE_PORT": "not-a-port"]
        defer { try? server.stop() }
        try await server.start()
        let clock = ContinuousClock()
        let started = clock.now
        do {
            try await server.waitReady(timeout: .seconds(10))
            Issue.record("waitReady returned for a server that cannot start")
        } catch let error as ServerError {
            guard case let .notReady(reason) = error else {
                Issue.record("unexpected \(error)")
                return
            }
            #expect(reason.contains("exited"))
            #expect(reason.contains("not-a-port")) // the log tail names the bad setting
        }
        #expect(clock.now - started < .seconds(20))
    }
}

// MARK: - Helpers

private func serverImage() throws -> String {
    struct ServerConfig: Decodable { var image: String }
    return try JSONDecoder().decode(
        ServerConfig.self,
        from: Data(contentsOf: livePackageDirectory.appendingPathComponent("config/server.json"))
    ).image
}

private func temporaryWorkDir() throws -> URL {
    // Resolve symlinks (macOS `/var` → `/private/var`) so Docker bind-mounts the real path.
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("live-server-\(UUID().uuidString)").resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Relative paths and sizes of every file under `root`, sorted.
func directoryListing(_ root: URL) throws -> [String] {
    let files = FileManager.default
    guard let enumerator = files.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return [] }
    var listing: [String] = []
    let prefix = root.resolvingSymlinksInPath().path + "/"
    for case let url as URL in enumerator {
        let values = try url.resolvingSymlinksInPath().resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        let path = url.resolvingSymlinksInPath().path.replacingOccurrences(of: prefix, with: "")
        listing.append(values.isRegularFile == true ? "\(path) \(values.fileSize ?? -1)" : "\(path)/")
    }
    return listing.sorted()
}

private func removeWorkDir(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

/// A started, ready server in a temporary work directory, removed with its directory afterwards.
private func withServer(_ mode: SecurityMode, _ body: (ServerControl) async throws -> Void) async throws {
    let workDir = try temporaryWorkDir()
    defer { removeWorkDir(workDir) }
    var server = ServerControl(image: try serverImage(), mode: mode, workDir: workDir)
    server.port = try freeLocalPort()
    defer { try? server.stop() }
    if mode == .tlsAuth { try server.generateCertificates() }
    try await server.start()
    try await server.waitReady()
    try await body(server)
}

private func client(_ connectionString: String) throws -> KurrentDBClient {
    KurrentDBClient(settings: try ClientSettings.parse(connectionString: connectionString))
}

private func withClient<T>(_ server: ServerControl, _ body: (KurrentDBClient) async throws -> T) async throws -> T {
    let client = try client(server.connectionString)
    defer { try? client.shutdown() }
    return try await body(client)
}

/// Events in `stream` (0 when it does not exist), link events counted as such.
private func count(_ client: KurrentDBClient, _ stream: String) async throws -> Int {
    do {
        var n = 0
        for try await _ in client.streams(specified: stream).read().lazy { n += 1 }
        return n
    } catch KurrentError.resourceNotFound {
        return 0
    }
}

private extension EventData {
    static var fixture: EventData {
        EventData(eventType: "BenchEvent", data: Data("{\"i\":0}".utf8), contentType: .json)
    }
}
