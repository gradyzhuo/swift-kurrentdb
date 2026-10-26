import Foundation
import LiveBenchCore

/// Reproducibility metadata archived with every cell result (spec: "Reproducibility metadata").
///
/// Every field is optional: the trial runner fills what it knows at cell time (server image, digest and effective
/// configuration, the effective scenario, client versions, `corpusReducedTo`); the environment collector (Task 11)
/// fills the rest. It never records host identity: no hostname, IP address or user name has a field here, and
/// `serverConfiguration` carries `ServerControl.effectiveConfiguration`, whose only network values are loopback and
/// whose `docker.user` is a numeric uid:gid.
struct RunMetadata: Codable, Sendable, Equatable {
    /// Commit of the swift-kurrentdb SDK under test (the Swift driver's `clientVersion`).
    var sdkCommit: String?
    /// Commit of the benchmark harness (`Benchmarks/Live`).
    var harnessCommit: String?
    var swiftToolchain: String?
    var dotnetRuntime: String?
    /// Exact `KurrentDB.Client` NuGet version of the .NET driver.
    var kurrentDBClientVersion: String?
    var ghzVersion: String?
    /// Build configuration and flags of the drivers (e.g. `swift build -c release`).
    var buildFlags: String?
    var serverImage: String?
    /// Registry digest (`sha256:…`) of `serverImage`.
    var serverImageDigest: String?
    /// `ServerControl.effectiveConfiguration`: server settings (secrets redacted) and container settings.
    var serverConfiguration: [String: String]?
    var scenario: ScenarioSettings?
    /// The `<driver> version` output of every client that ran.
    var clients: [DriverVersion]?
    var runnerImageVersion: String?
    var cpuModel: String?
    /// Set when the catch-up corpus was reduced to fit the disk budget; the report states it.
    var corpusReducedTo: Int?
    /// UTC date (`YYYY-MM-DD`) the cell ran; names the results bundle.
    var runDate: String?

    /// The effective scenario of a cell: what every trial's `EffectiveScenario` shares.
    struct ScenarioSettings: Codable, Sendable, Equatable {
        var rates: [Double]
        var rounds: Int
        var warmupSeconds: Double
        var measureSeconds: Double
        var drainSeconds: Double
        var inFlightCap: Int
        var deadlineMillis: Int
        var seed: UInt64
        /// `run-cell --smoke`: one round, the first rate, short phases. Never a published result.
        var smoke: Bool
    }
}

extension RunMetadata {
    /// Build configuration of the drivers when the environment does not say (`LIVE_BENCH_BUILD_FLAGS`).
    static let defaultBuildFlags = "swift build -c release; dotnet build -c Release -p:RestoreLockedMode=true"

    /// The metadata of the machine and checkout the cell runs on, from the sources named below and nothing else:
    ///
    /// - commits: `LIVE_BENCH_SDK_COMMIT` / `LIVE_BENCH_HARNESS_COMMIT`, else `GITHUB_SHA` (the harness lives in the SDK
    ///   repository, so one checkout is both);
    /// - runner image: GitHub's `ImageOS` and `ImageVersion`;
    /// - toolchains: `swift --version` (first line) and `dotnet --version`, through `command`;
    /// - CPU model: `model name` of `/proc/cpuinfo` (Linux), else `sysctl -n machdep.cpu.brand_string` (macOS);
    /// - build flags: `LIVE_BENCH_BUILD_FLAGS`, else `defaultBuildFlags`; run date: `now` in UTC.
    ///
    /// It never reads the host name, user name or addresses, and every collected string goes through
    /// `HostRedaction.scrub` (plus the values of `HOSTNAME`, `HOST`, `USER` and `LOGNAME`), so a tool that prints a
    /// home directory or an address cannot leak it into the results.
    static func collect(
        environment: [String: String],
        readFile: (String) -> String? = { try? String(contentsOfFile: $0, encoding: .utf8) },
        command: ([String]) -> String? = RunMetadata.commandOutput,
        now: Date = Date()
    ) -> RunMetadata {
        func value(_ key: String) -> String? {
            environment[key].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        func firstLine(_ text: String?) -> String? {
            text?.split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
        }

        var metadata = RunMetadata()
        metadata.sdkCommit = value("LIVE_BENCH_SDK_COMMIT") ?? value("GITHUB_SHA")
        metadata.harnessCommit = value("LIVE_BENCH_HARNESS_COMMIT") ?? value("GITHUB_SHA")
        if let os = value("ImageOS") {
            metadata.runnerImageVersion = [os, value("ImageVersion")].compactMap { $0 }.joined(separator: " ")
        }
        metadata.swiftToolchain = firstLine(command(["swift", "--version"]))
        metadata.dotnetRuntime = firstLine(command(["dotnet", "--version"]))
        metadata.buildFlags = value("LIVE_BENCH_BUILD_FLAGS") ?? defaultBuildFlags
        if let cpuinfo = readFile("/proc/cpuinfo") {
            metadata.cpuModel = cpuinfo.split(whereSeparator: \.isNewline)
                .first { $0.hasPrefix("model name") }
                .flatMap { $0.split(separator: ":", maxSplits: 1).last }
                .map { $0.trimmingCharacters(in: .whitespaces) }
        } else {
            metadata.cpuModel = firstLine(command(["sysctl", "-n", "machdep.cpu.brand_string"]))
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(identifier: "UTC")
        metadata.runDate = formatter.string(from: now)

        let identities = ["HOSTNAME", "HOST", "USER", "LOGNAME"].compactMap(value)
        return metadata.redacted(also: identities)
    }

    /// stdout of a tool found on `PATH`, nil when it is missing or fails.
    static func commandOutput(_ arguments: [String]) -> String? {
        guard let tool = arguments.first, let output = try? Shell.capture(tool, Array(arguments.dropFirst())), output.status == 0 else {
            return nil
        }
        return output.stdout
    }

    /// `self` with every nil field taken from `other` (the drivers' own reports win over the environment's).
    func filling(from other: RunMetadata) -> RunMetadata {
        var merged = self
        merged.sdkCommit = sdkCommit ?? other.sdkCommit
        merged.harnessCommit = harnessCommit ?? other.harnessCommit
        merged.swiftToolchain = swiftToolchain ?? other.swiftToolchain
        merged.dotnetRuntime = dotnetRuntime ?? other.dotnetRuntime
        merged.kurrentDBClientVersion = kurrentDBClientVersion ?? other.kurrentDBClientVersion
        merged.ghzVersion = ghzVersion ?? other.ghzVersion
        merged.buildFlags = buildFlags ?? other.buildFlags
        merged.serverImage = serverImage ?? other.serverImage
        merged.serverImageDigest = serverImageDigest ?? other.serverImageDigest
        merged.serverConfiguration = serverConfiguration ?? other.serverConfiguration
        merged.scenario = scenario ?? other.scenario
        merged.clients = clients ?? other.clients
        merged.runnerImageVersion = runnerImageVersion ?? other.runnerImageVersion
        merged.cpuModel = cpuModel ?? other.cpuModel
        merged.corpusReducedTo = corpusReducedTo ?? other.corpusReducedTo
        merged.runDate = runDate ?? other.runDate
        return merged
    }

    /// Every string value through `HostRedaction.scrub`, each of `identities` (3+ characters) replaced too. Fails
    /// closed: if the metadata cannot be redacted, nothing of it is kept.
    func redacted(also identities: [String] = []) -> RunMetadata {
        (try? HostRedaction.scrubbing(self, also: identities)) ?? RunMetadata()
    }
}

/// Removes host identity from text bound for the results: home directories (`/Users/<name>`, `/home/<name>`, also
/// with JSON-escaped slashes in raw text) become `~`, private IPv4 addresses (RFC 1918, all four octets) become
/// `<private-ip>`. Loopback stays. Version strings such as `10.0.1` have three parts and are not addresses.
enum HostRedaction {
    static let privateIPv4 = #"\b(?:10\.\d{1,3}|192\.168|172\.(?:1[6-9]|2\d|3[01]))\.\d{1,3}\.\d{1,3}\b"#
    static let home = #"\\?/(?:Users|home)\\?/[^/\\\s"'<>:;,)]+"#

    struct Failure: Error, CustomStringConvertible {
        var description: String
    }

    /// Scrubs one piece of text (a string value, or a raw log).
    static func scrub(_ text: String, also identities: [String] = []) -> String {
        // `/Users/alice/x` → `~/x`; in raw text, JSON-escaped `\/home\/bob\/y` → `~\/y`.
        var result = text.replacingOccurrences(of: home, with: "~", options: .regularExpression)
        result = result.replacingOccurrences(of: privateIPv4, with: "<private-ip>", options: .regularExpression)
        for identity in identities where identity.count >= 3 {
            result = result.replacingOccurrences(of: identity, with: "<redacted>")
        }
        return result
    }

    /// `value` with every string **value** inside it, however deeply nested, scrubbed; object keys are left alone,
    /// so the structure always decodes again. Throws rather than ever returning the unredacted value.
    static func scrubbing<T: Codable>(_ value: T, also identities: [String] = []) throws -> T {
        let encoder = JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "+inf", negativeInfinity: "-inf", nan: "nan")
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "+inf", negativeInfinity: "-inf", nan: "nan")
        do {
            let tree = try JSONSerialization.jsonObject(with: encoder.encode(value), options: [.fragmentsAllowed])
            let scrubbed = try JSONSerialization.data(withJSONObject: scrubValues(tree, also: identities), options: [.fragmentsAllowed])
            return try decoder.decode(T.self, from: scrubbed)
        } catch {
            throw Failure(description: "cannot redact \(T.self): \(error)")
        }
    }

    /// A JSON document (raw bytes) with its string values scrubbed; nil when `data` is not JSON.
    static func scrubbingJSON(_ data: Data) -> Data? {
        guard let tree = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        return try? JSONSerialization.data(
            withJSONObject: scrubValues(tree, also: []), options: [.fragmentsAllowed, .prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }

    private static func scrubValues(_ node: Any, also identities: [String]) -> Any {
        switch node {
        case let string as String: scrub(string, also: identities)
        case let array as [Any]: array.map { scrubValues($0, also: identities) }
        case let object as [String: Any]: object.mapValues { scrubValues($0, also: identities) }
        default: node
        }
    }
}
