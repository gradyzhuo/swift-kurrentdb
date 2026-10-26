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
