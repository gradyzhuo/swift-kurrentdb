import Foundation
@testable import LiveOrchestrator
import Testing

/// `ServerControl` and `Seeder` pieces that need no Docker.
@Suite("Server control")
struct ServerControlTests {
    @Test func copyReplacingLeavesExactlyTheSourceAndNoNesting() throws {
        try withTemporaryDirectory { root in
            let source = root.appendingPathComponent("snapshot")
            let destination = root.appendingPathComponent("data")
            try write("seeded", to: source.appendingPathComponent("chunk-000000.000000"))
            try write("index", to: source.appendingPathComponent("index/table"))
            try write("newer", to: destination.appendingPathComponent("chunk-000000.000000"))
            try write("stale", to: destination.appendingPathComponent("junk/extra"))

            try ServerControl.copyReplacing(source, with: destination)

            #expect(try directoryListing(destination) == directoryListing(source))
            #expect(try String(contentsOf: destination.appendingPathComponent("chunk-000000.000000"), encoding: .utf8) == "seeded")
            #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("snapshot").path))
        }
    }

    @Test(.enabled(if: getuid() != 0, "root can remove anything"))
    func copyReplacingThrowsWhenTheDestinationCannotBeRemoved() throws {
        try withTemporaryDirectory { root in
            let source = root.appendingPathComponent("snapshot")
            let destination = root.appendingPathComponent("data")
            try write("seeded", to: source.appendingPathComponent("chunk"))
            let locked = destination.appendingPathComponent("locked")
            try write("stale", to: locked.appendingPathComponent("file"))
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }

            #expect(throws: (any Error).self) { try ServerControl.copyReplacing(source, with: destination) }
            // Nothing was copied into (or nested inside) the half-removed destination.
            #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("snapshot").path))
            #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("chunk").path))
        }
    }

    @Test func copyReplacingNeedsTheSource() throws {
        try withTemporaryDirectory { root in
            #expect(throws: ServerError.self) {
                try ServerControl.copyReplacing(root.appendingPathComponent("missing"), with: root.appendingPathComponent("data"))
            }
        }
    }

    @Test func projectionPositionsCompareAsCommitPreparePairs() {
        #expect(LogPosition(projectionPosition: "C:13461/P:13461") == LogPosition(commit: 13461, prepare: 13461))
        #expect(LogPosition(projectionPosition: "C:0/P:-1") == nil)
        #expect(LogPosition(projectionPosition: "") == nil)
        #expect(LogPosition(commit: 10, prepare: 5) < LogPosition(commit: 10, prepare: 6))
        #expect(LogPosition(commit: 9, prepare: 99) < LogPosition(commit: 10, prepare: 0))
    }

    @Test func effectiveConfigurationRecordsContainerSettingsWithoutTheSecret() {
        var server = ServerControl(image: "kurrentplatform/kurrentdb:26.2.3", mode: .plainAuth, cpuset: "0,1", workDir: URL(fileURLWithPath: "/tmp/x"))
        server.networking = .host
        let configuration = server.effectiveConfiguration
        #expect(configuration["docker.image"] == "kurrentplatform/kurrentdb:26.2.3")
        #expect(configuration["docker.cpuset"] == "0,1")
        #expect(configuration["docker.network"] == "host")
        #expect(configuration["docker.user"] == "\(getuid()):\(getgid())")
        #expect(configuration["KURRENTDB_DISABLE_TLS"] == "true")
        #expect(configuration["KURRENTDB_CLUSTER_SECRET"] == "<redacted>")
        #expect(configuration["KURRENTDB_INSECURE"] == nil)
    }
}

private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("live-server-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try body(root)
}

private func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}
