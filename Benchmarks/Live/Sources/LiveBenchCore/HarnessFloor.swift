import Foundation

/// A driver's harness floor (driver contract rule 10): the open loop with an operation that returns immediately, after
/// a warmup window at the same rate. `<driver> floor` prints it as one JSON object; the .NET driver prints the same
/// fields. Latencies are microseconds; `cpuSeconds` is process CPU over the measured window; `maxRssBytes` the process
/// peak.
public struct HarnessFloor: Codable, Equatable, Sendable {
    public var rate: Double
    public var seconds: Double
    public var scheduled: Int
    public var succeeded: Int
    public var p50Micros: UInt64
    public var p99Micros: UInt64
    public var p999Micros: UInt64
    public var maxMicros: UInt64
    public var cpuSeconds: Double
    public var maxRssBytes: UInt64
    public var runtime: String

    /// The JSON field names every driver's `floor` prints.
    public static let fieldNames: Set<String> = [
        "rate", "seconds", "scheduled", "succeeded", "p50Micros", "p99Micros", "p999Micros", "maxMicros", "cpuSeconds",
        "maxRssBytes", "runtime",
    ]

    public init(
        rate: Double, seconds: Double, scheduled: Int, succeeded: Int, p50Micros: UInt64, p99Micros: UInt64, p999Micros: UInt64,
        maxMicros: UInt64, cpuSeconds: Double, maxRssBytes: UInt64, runtime: String
    ) {
        self.rate = rate
        self.seconds = seconds
        self.scheduled = scheduled
        self.succeeded = succeeded
        self.p50Micros = p50Micros
        self.p99Micros = p99Micros
        self.p999Micros = p999Micros
        self.maxMicros = maxMicros
        self.cpuSeconds = cpuSeconds
        self.maxRssBytes = maxRssBytes
        self.runtime = runtime
    }
}

/// Measures the floor of `runOpenLoop` with a no-op operation: a `warmupSeconds` window, then `seconds` measured, both
/// at `rate`, with the trial's in-flight cap (256), deadline (5 s) and a 1 s drain, as the .NET driver's `floor`.
public func measureHarnessFloor(rate: Double, seconds: Double, warmupSeconds: Double, runtime: String = swiftLanguageMode) async -> HarnessFloor {
    func config(_ length: Double) -> OpenLoopConfig {
        OpenLoopConfig(rate: rate, duration: .nanoseconds(Int64((length * 1e9).rounded())), inFlightCap: 256, deadline: .seconds(5), drain: .seconds(1))
    }
    if warmupSeconds > 0 { _ = await runOpenLoop(config(warmupSeconds)) { _ in } }
    let before = ProcessUsage.current()
    let r = await runOpenLoop(config(seconds)) { _ in }
    let after = ProcessUsage.current()
    let h = r.histogram
    func value(_ p: Double) -> UInt64 { r.succeeded > 0 ? h.valueAtPercentile(p) : 0 }
    return HarnessFloor(
        rate: rate, seconds: seconds, scheduled: r.scheduled, succeeded: r.succeeded,
        p50Micros: value(50), p99Micros: value(99), p999Micros: value(99.9), maxMicros: value(100),
        cpuSeconds: max(0, (after.user - before.user) + (after.system - before.system)), maxRssBytes: after.maxRss, runtime: runtime
    )
}

/// The Swift language mode this was compiled with ("swift 6.2"); the full toolchain is in the run metadata.
public var swiftLanguageMode: String {
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
