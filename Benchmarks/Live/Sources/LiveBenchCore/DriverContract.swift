import Foundation

/// Where a driver starts each operation's latency clock. Full definition: `docs/driver-contract.md`.
public enum Timing: String, Codable, Sendable {
    /// From the scheduled instant (min of scheduled and actual launch). Every in-process driver uses this.
    case scheduled
    /// From the start of the RPC (external tools such as ghz that cannot see the schedule); never a headline comparison.
    case rpcStart
}

/// Event counts a driver reports so the orchestrator can reject a trial that lost or corrupted data.
/// Per-kind meaning is in `docs/driver-contract.md`.
public struct Validation: Codable, Equatable, Sendable {
    public var expectedEvents: Int
    public var receivedEvents: Int
    public var payloadSizesOk: Bool

    public init(expectedEvents: Int, receivedEvents: Int, payloadSizesOk: Bool) {
        self.expectedEvents = expectedEvents
        self.receivedEvents = receivedEvents
        self.payloadSizesOk = payloadSizesOk
    }
}

/// `result.json`, written by `<driver> run` next to `histogram.json`.
public struct TrialResult: Codable, Equatable, Sendable {
    public var client: String
    public var cellId: String
    public var targetRate: Double
    public var timing: Timing
    public var scheduled: Int
    public var succeeded: Int
    public var failed: Int
    public var dropped: Int
    public var timedOut: Int
    public var measuredSeconds: Double
    public var cpuUserSeconds: Double
    public var cpuSystemSeconds: Double
    public var maxRssBytes: UInt64
    public var ackEnqueued: Int?
    public var uniqueDeliveries: Int?
    public var redeliveries: Int?
    public var catchUpSeconds: Double?
    public var validation: Validation

    public init(
        client: String, cellId: String, targetRate: Double, timing: Timing,
        scheduled: Int, succeeded: Int, failed: Int, dropped: Int, timedOut: Int,
        measuredSeconds: Double, cpuUserSeconds: Double, cpuSystemSeconds: Double, maxRssBytes: UInt64,
        ackEnqueued: Int? = nil, uniqueDeliveries: Int? = nil, redeliveries: Int? = nil, catchUpSeconds: Double? = nil,
        validation: Validation
    ) {
        self.client = client
        self.cellId = cellId
        self.targetRate = targetRate
        self.timing = timing
        self.scheduled = scheduled
        self.succeeded = succeeded
        self.failed = failed
        self.dropped = dropped
        self.timedOut = timedOut
        self.measuredSeconds = measuredSeconds
        self.cpuUserSeconds = cpuUserSeconds
        self.cpuSystemSeconds = cpuSystemSeconds
        self.maxRssBytes = maxRssBytes
        self.ackEnqueued = ackEnqueued
        self.uniqueDeliveries = uniqueDeliveries
        self.redeliveries = redeliveries
        self.catchUpSeconds = catchUpSeconds
        self.validation = validation
    }
}

/// Output of `<driver> version`.
public struct DriverVersion: Codable, Equatable, Sendable {
    public var client: String
    public var clientVersion: String
    public var runtime: String

    public init(client: String, clientVersion: String, runtime: String) {
        self.client = client
        self.clientVersion = clientVersion
        self.runtime = runtime
    }
}
