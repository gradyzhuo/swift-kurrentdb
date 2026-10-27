import Foundation
import KurrentDB
import Synchronization

/// How the server is secured. Both modes keep authentication and authorization on; they differ only in TLS.
enum SecurityMode: String, Codable, Sendable {
    /// TLS with certificates from `es-gencert-cli`, authentication on (the headline configuration).
    case tlsAuth
    /// TLS off, authentication still on: `--disable-tls` with a `--cluster-secret` (never `--insecure`, which also
    /// turns authentication off and would confound the TLS-cost comparison).
    case plainAuth
}

enum ServerError: Error, CustomStringConvertible {
    /// The server did not accept an authenticated read in time, or its container exited; `reason` carries the
    /// container state and the tail of its log.
    case notReady(reason: String)
    /// A data-directory operation needs the server stopped.
    case stillRunning(String)
    case missingDirectory(String)
    /// The server did not exit cleanly on `stop()`; its data directory is not fit for a snapshot.
    case uncleanStop(reason: String)
    case dataDirectory(String)
    case noImageDigest(String)

    var description: String {
        switch self {
        case let .notReady(reason): "server not ready: \(reason)"
        case let .stillRunning(name): "container \(name) is still running; stop the server first"
        case let .missingDirectory(path): "\(path) does not exist (snapshot() needs data/, restoreSnapshot() needs snapshot/)"
        case let .uncleanStop(reason): "server did not stop cleanly: \(reason)"
        case let .dataDirectory(problem): "data directory: \(problem)"
        case let .noImageDigest(image): "image \(image) has no repository digest (pull it from the registry)"
        }
    }
}

/// One single-node KurrentDB container with its certificates, data directory and snapshot in `workDir`.
///
/// Layout of `workDir`: `certs/` (CA and node certificate), `data/` (bind-mounted as the database directory),
/// `snapshot/` (a copy of `data/` taken right after seeding), `logs/` (the server's log directory).
///
/// The container runs with the caller's uid/gid so every file in `workDir` stays owned by the caller (`cp -a`, `rm`
/// need no `sudo`), pinned to `cpuset` with `--cpuset-cpus`. On Linux it uses the host network (no docker-proxy in
/// the data path) and listens on `127.0.0.1:<port>`; elsewhere (local development) the port is mapped. Either way the
/// node advertises `127.0.0.1:<port>` to clients, because the SDKs connect to the advertised address, and the
/// certificate's SANs are `127.0.0.1` and `localhost`.
struct ServerControl: Sendable {
    enum Networking: Sendable {
        /// `--network host`, node bound to `127.0.0.1:<port>` (Linux, CI).
        case host
        /// `-p 127.0.0.1:<port>:2113` (Docker Desktop, local development).
        case portMapped
    }

    static let certificateImage = "eventstore/es-gencert-cli:1.0.2"

    let image: String
    let mode: SecurityMode
    let cpuset: String
    let workDir: URL
    /// Container name, unique per `ServerControl` value.
    let containerName: String
    /// Client port on 127.0.0.1.
    var port = 2113
    #if os(Linux)
    var networking = Networking.host
    #else
    var networking = Networking.portMapped
    #endif
    /// Extra `KURRENTDB_*` settings (tests use it to make the server fail on start).
    var extraEnvironment: [String: String] = [:]
    /// Required by `--disable-tls`; only nodes of a cluster use it. Random per instance, never recorded.
    private let clusterSecret: String

    init(image: String, mode: SecurityMode, cpuset: String = "0,1", workDir: URL) {
        self.image = image
        self.mode = mode
        self.cpuset = cpuset
        self.workDir = workDir
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        containerName = "live-bench-server-\(token.prefix(12))"
        clusterSecret = UUID().uuidString
    }

    var certsDirectory: URL { workDir.appendingPathComponent("certs") }
    var dataDirectory: URL { workDir.appendingPathComponent("data") }
    var snapshotDirectory: URL { workDir.appendingPathComponent("snapshot") }
    var logsDirectory: URL { workDir.appendingPathComponent("logs") }
    var caFile: URL { certsDirectory.appendingPathComponent("ca/ca.crt") }

    /// Admin credentials, 127.0.0.1 (a SAN of the node certificate), TLS per `mode`; no other settings (headline
    /// runs use each client's defaults).
    var connectionString: String {
        switch mode {
        case .tlsAuth: "kurrentdb://admin:changeit@127.0.0.1:\(port)?tls=true&tlsCaFile=\(Self.queryEncoded(caFile.path))"
        case .plainAuth: "kurrentdb://admin:changeit@127.0.0.1:\(port)?tls=false"
        }
    }

    /// The server settings passed to the container (cluster secret redacted) plus the container-level settings
    /// (`docker.image`, `docker.cpuset`, `docker.network`, `docker.user`), for the run metadata.
    var effectiveConfiguration: [String: String] {
        var settings = environment
        if settings["KURRENTDB_CLUSTER_SECRET"] != nil { settings["KURRENTDB_CLUSTER_SECRET"] = "<redacted>" }
        settings["docker.image"] = image
        settings["docker.cpuset"] = cpuset
        switch networking {
        case .host: settings["docker.network"] = "host"
        case .portMapped: settings["docker.network"] = "bridge, port \(port) mapped to 2113"
        }
        settings["docker.user"] = Self.hostUser
        return settings
    }

    private var environment: [String: String] {
        var settings = [
            "KURRENTDB_CLUSTER_SIZE": "1",
            "KURRENTDB_RUN_PROJECTIONS": "System",
            "KURRENTDB_START_STANDARD_PROJECTIONS": "true",
            "KURRENTDB_ADVERTISE_HOST_TO_CLIENT_AS": "127.0.0.1",
            "KURRENTDB_ADVERTISE_NODE_PORT_TO_CLIENT_AS": "\(port)",
            // The server gzips every response message for a client that advertises gzip (.NET and ghz do, the Swift
            // SDK does not), costing it 2-4x the CPU on long reads for ~10% fewer bytes on 300 B events: off, so every
            // client gets the same server work.
            "KURRENTDB_COMPRESSION_LEVEL": "NoCompression",
        ]
        switch mode {
        case .tlsAuth:
            settings["KURRENTDB_TRUSTED_ROOT_CERTIFICATES_PATH"] = "/certs/ca"
            settings["KURRENTDB_CERTIFICATE_FILE"] = "/certs/node/node.crt"
            settings["KURRENTDB_CERTIFICATE_PRIVATE_KEY_FILE"] = "/certs/node/node.key"
        case .plainAuth:
            settings["KURRENTDB_DISABLE_TLS"] = "true"
            settings["KURRENTDB_CLUSTER_SECRET"] = clusterSecret
        }
        if networking == .host {
            settings["KURRENTDB_NODE_IP"] = "127.0.0.1"
            settings["KURRENTDB_NODE_PORT"] = "\(port)"
            settings["KURRENTDB_REPLICATION_IP"] = "127.0.0.1"
        }
        settings.merge(extraEnvironment) { _, extra in extra }
        return settings
    }

    // MARK: - Certificates

    /// Creates a CA and a node certificate for `127.0.0.1` / `localhost` in `certs/`, replacing any previous ones.
    func generateCertificates() throws {
        try? FileManager.default.removeItem(at: certsDirectory)
        try FileManager.default.createDirectory(at: certsDirectory, withIntermediateDirectories: true)
        let run = ["run", "--rm", "--user", Self.hostUser, "-v", "\(certsDirectory.path):/certs", Self.certificateImage]
        try Shell.run("docker", run + ["create-ca", "-out", "/certs/ca"])
        try Shell.run("docker", run + [
            "create-node", "-ca-certificate", "/certs/ca/ca.crt", "-ca-key", "/certs/ca/ca.key",
            "-out", "/certs/node", "-ip-addresses", "127.0.0.1", "-dns-names", "localhost",
        ])
    }

    // MARK: - Lifecycle

    /// Starts a new container on the existing `data/` (created empty if missing). Returns once the container runs;
    /// `waitReady` decides whether the server came up.
    func start() async throws {
        for directory in [dataDirectory, logsDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        var arguments = [
            "run", "-d", "--name", containerName, "--label", "live-bench-server=1",
            "--cpuset-cpus", cpuset, "--user", Self.hostUser,
            "-v", "\(dataDirectory.path):/var/lib/kurrentdb",
            "-v", "\(logsDirectory.path):/var/log/kurrentdb",
            // An arbitrary uid has no home directory in the image; .NET wants a writable one.
            "-e", "HOME=/tmp",
        ]
        if mode == .tlsAuth {
            arguments += ["-v", "\(certsDirectory.path):/certs:ro"]
        }
        switch networking {
        case .host: arguments += ["--network", "host"]
        case .portMapped: arguments += ["-p", "127.0.0.1:\(port):2113"]
        }
        for (key, value) in environment.sorted(by: { $0.key < $1.key }) {
            arguments += ["-e", "\(key)=\(value)"]
        }
        arguments.append(image)
        try Shell.run("docker", arguments)
    }

    /// Waits until the server answers an authenticated `$all` read over `connectionString` (so TLS, authentication
    /// and leadership all work). Throws `ServerError.notReady` with the container log tail as soon as the container
    /// is no longer running, or after `timeout`.
    func waitReady(timeout: Duration = .seconds(120)) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        let client = KurrentDBClient(settings: try ClientSettings.parse(connectionString: connectionString))
        defer { try? client.shutdown() }
        var lastError = "no attempt"
        while true {
            if let state = try containerState(), state.status != "running" {
                throw ServerError.notReady(reason: "container \(state.status) (exit code \(state.exitCode)); log tail:\n\(logTail())")
            }
            let remaining = clock.now.duration(to: deadline)
            guard remaining > .zero else { break }
            do {
                try await withTimeout(min(.seconds(5), remaining)) {
                    for try await _ in client.allStreams.read(configure: { $0.limit = 1 }).lazy { break }
                }
                return
            } catch {
                lastError = "\(error)"
            }
            guard clock.now < deadline else { break }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw ServerError.notReady(reason: "no successful read within \(timeout) (last error: \(lastError)); log tail:\n\(logTail())")
    }

    /// Stops the server gracefully (so the data directory is consistent) and removes its container. Does nothing
    /// when there is no container. Throws `ServerError.uncleanStop` (after removing the container) when the server
    /// did not exit cleanly (exit code other than 0 or 143, e.g. 137 when `docker stop` had to kill it after 60 s):
    /// its data directory must not be snapshotted.
    func stop() throws {
        let stopped = try Shell.capture("docker", ["stop", "-t", "60", containerName])
        if stopped.status != 0 {
            guard stopped.stderr.contains("No such container") else {
                throw ShellError(command: ["docker", "stop", containerName], status: stopped.status, stderr: stopped.stderr)
            }
            return
        }
        let state = try containerState()
        let tail = logTail()
        try Shell.run("docker", ["rm", "-f", containerName])
        guard let state else { return }
        guard state.status == "exited", Self.cleanExitCodes.contains(state.exitCode) else {
            throw ServerError.uncleanStop(reason: "container \(state.status) with exit code \(state.exitCode); log tail:\n\(tail)")
        }
    }

    /// 0: the server shut down on its own; 143: 128 + SIGTERM, the signal `docker stop` sends first.
    static let cleanExitCodes: Set<Int> = [0, 143]

    // MARK: - Data directory

    /// Copies the stopped server's `data/` to `snapshot/` (`cp -a`), replacing an earlier snapshot.
    func snapshot() throws {
        try requireStopped()
        try Self.copyReplacing(dataDirectory, with: snapshotDirectory)
    }

    /// Replaces the stopped server's `data/` with a copy of `snapshot/` (`cp -a`).
    func restoreSnapshot() throws {
        try requireStopped()
        try Self.copyReplacing(snapshotDirectory, with: dataDirectory)
    }

    /// `cp -a source destination` after removing `destination`. A removal that fails throws, and the destination is
    /// checked to be gone first: `cp -a` into an existing directory would nest the copy inside it (`data/snapshot/…`)
    /// and leave the old files in place, so a server would silently restart on stale data.
    static func copyReplacing(_ source: URL, with destination: URL) throws {
        let files = FileManager.default
        guard files.fileExists(atPath: source.path) else {
            throw ServerError.missingDirectory(source.path)
        }
        if files.fileExists(atPath: destination.path) {
            try files.removeItem(at: destination)
        }
        guard !files.fileExists(atPath: destination.path) else {
            throw ServerError.dataDirectory("\(destination.path) still exists after removal")
        }
        try Shell.run("cp", ["-a", source.path, destination.path])
    }

    /// Drops the OS page cache so no trial inherits another's warm cache (Linux, passwordless `sudo`). Elsewhere it
    /// only warns: Docker Desktop's VM cache is out of reach, which is acceptable for local development runs.
    func dropCaches() throws {
        #if os(Linux)
        try Shell.run("sh", ["-c", "sync && echo 3 | sudo -n tee /proc/sys/vm/drop_caches > /dev/null"])
        #else
        FileHandle.standardError.write(Data("warning: dropCaches() is a no-op on this platform\n".utf8))
        #endif
    }

    // MARK: - Metadata

    /// The registry digest (`sha256:…`) of `image`, for the run metadata.
    func imageDigest() throws -> String {
        let output = try Shell.run("docker", ["image", "inspect", "--format", "{{json .RepoDigests}}", image])
        let digests = try JSONDecoder().decode([String].self, from: Data(output.utf8))
        guard let digest = digests.lazy.compactMap({ $0.split(separator: "@").last }).first(where: { $0.hasPrefix("sha256:") }) else {
            throw ServerError.noImageDigest(image)
        }
        return String(digest)
    }

    // MARK: - Private

    /// Percent-encodes everything but unreserved characters and `/`, so any temporary path survives as one value.
    private static func queryEncoded(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static var hostUser: String { "\(getuid()):\(getgid())" }

    /// `nil` when the container does not exist.
    private func containerState() throws -> (status: String, exitCode: Int)? {
        let result = try Shell.capture("docker", ["inspect", "--format", "{{.State.Status}} {{.State.ExitCode}}", containerName])
        guard result.status == 0 else { return nil }
        let fields = result.stdout.split(separator: " ").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return (fields.first ?? "unknown", fields.count > 1 ? Int(fields[1]) ?? -1 : -1)
    }

    private func requireStopped() throws {
        if let state = try containerState(), state.status == "running" {
            throw ServerError.stillRunning(containerName)
        }
    }

    private func logTail() -> String {
        guard let logs = try? Shell.capture("docker", ["logs", "--tail", "40", containerName]) else { return "(no log)" }
        return String((logs.stdout + logs.stderr).suffix(4000))
    }
}

struct TimeoutError: Error, CustomStringConvertible {
    let limit: Duration
    var description: String { "timed out after \(limit)" }
}

/// Runs `operation`, throwing `TimeoutError` if it has not finished after `limit`. The operation is then cancelled
/// and abandoned: an RPC that ignores cancellation (e.g. one sent while the server is still starting) cannot hold
/// the caller, unlike a task-group child.
func withTimeout<T: Sendable>(_ limit: Duration, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        let once = ResumeOnce(continuation)
        let work = Task {
            do { once.resume(.success(try await operation())) } catch { once.resume(.failure(error)) }
        }
        Task {
            try? await Task.sleep(for: limit)
            work.cancel()
            once.resume(.failure(TimeoutError(limit: limit)))
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
