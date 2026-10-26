import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing

/// `true` when Docker-gated tests should run (env `LIVE_BENCH_DOCKER=1`).
let docker = ProcessInfo.processInfo.environment["LIVE_BENCH_DOCKER"] == "1"

/// The `Benchmarks/Live` package directory, found from this source file.
let livePackageDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // Support
    .deletingLastPathComponent() // LiveOrchestratorTests
    .deletingLastPathComponent() // Tests
    .deletingLastPathComponent() // Live

/// A throwaway insecure single-node KurrentDB container (image from `config/server.json`) on a free host port, with
/// all projections running. Tests reach it through `LiveServer.current`, which the `.liveServer` suite trait binds.
struct LiveServer: Sendable {
    @TaskLocal static var current: LiveServer?

    let containerId: String
    let port: Int

    var connectionString: String { "kurrentdb://127.0.0.1:\(port)?tls=false" }

    static func start() async throws -> LiveServer {
        struct ServerConfig: Decodable { var image: String }
        let config = try JSONDecoder().decode(
            ServerConfig.self,
            from: Data(contentsOf: livePackageDirectory.appendingPathComponent("config/server.json"))
        )
        // The SDK connects to the endpoint the node advertises in gossip (default settings), so the node must
        // advertise the mapped host port, which therefore has to be chosen before the container starts.
        let port = try freeLocalPort()
        let containerId = try runTool("docker", [
            "run", "-d", "--rm", "--label", "live-bench-test=1",
            "-p", "127.0.0.1:\(port):2113",
            "-e", "KURRENTDB_CLUSTER_SIZE=1",
            "-e", "KURRENTDB_RUN_PROJECTIONS=All",
            "-e", "KURRENTDB_START_STANDARD_PROJECTIONS=true",
            "-e", "KURRENTDB_INSECURE=true",
            "-e", "KURRENTDB_ADVERTISE_HOST_TO_CLIENT_AS=127.0.0.1",
            "-e", "KURRENTDB_ADVERTISE_NODE_PORT_TO_CLIENT_AS=\(port)",
            config.image,
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let server = LiveServer(containerId: containerId, port: port)
            try await server.waitUntilLive(timeout: .seconds(120))
            return server
        } catch {
            _ = try? runTool("docker", ["rm", "-f", containerId])
            throw error
        }
    }

    func stop() {
        _ = try? runTool("docker", ["rm", "-f", containerId])
    }

    private func waitUntilLive(timeout: Duration) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        let url = URL(string: "http://127.0.0.1:\(port)/health/live")!
        while clock.now < deadline {
            if let (_, response) = try? await URLSession.shared.data(from: url),
               let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                return
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw HarnessError("server on port \(port) was not live within \(timeout)")
    }
}

/// Suite trait: starts one `LiveServer` for the whole suite when Docker tests are enabled, and removes it afterwards.
struct LiveServerTrait: SuiteTrait, TestScoping {
    var isRecursive: Bool { false }

    func provideScope(
        for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void
    ) async throws {
        guard docker else {
            try await function()
            return
        }
        let server = try await LiveServer.start()
        defer { server.stop() }
        try await LiveServer.$current.withValue(server) {
            try await function()
        }
    }
}

extension Trait where Self == LiveServerTrait {
    /// One throwaway KurrentDB container shared by the tests of the suite (Docker-gated).
    static var liveServer: Self { LiveServerTrait() }
}

/// A TCP port on 127.0.0.1 that was free a moment ago (bound to port 0, then released).
private func freeLocalPort() throws -> Int {
    #if os(Linux)
    let fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
    #else
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    #endif
    guard fd >= 0 else { throw HarnessError("socket() failed") }
    defer { close(fd) }
    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = 0
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let bound = withUnsafeMutablePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { pointer in
            bind(fd, pointer, length) == 0 && getsockname(fd, pointer, &length) == 0
        }
    }
    guard bound else { throw HarnessError("cannot bind a local port") }
    return Int(UInt16(bigEndian: address.sin_port))
}

struct HarnessError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// Runs a command found on `PATH` to completion and returns its stdout; throws with stderr on a non-zero exit.
@discardableResult
func runTool(_ tool: String, _ arguments: [String]) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [tool] + arguments
    let stdout = Pipe(), stderr = Pipe()
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    let output = stdout.fileHandleForReading.readDataToEndOfFile()
    let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw HarnessError("\(tool) \(arguments.joined(separator: " ")) exited \(process.terminationStatus): \(String(decoding: errorOutput, as: UTF8.self))")
    }
    return String(decoding: output, as: UTF8.self)
}
