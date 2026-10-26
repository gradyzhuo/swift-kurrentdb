import Foundation

/// Fixed gate thresholds (see the spec's "Fixed initial parameters").
public enum EvaluationThresholds {
    /// A step is sustained when succeeded / measuredSeconds reaches this fraction of the target rate.
    public static let sustainedRateFraction = 0.99
    /// Maximum (failed + dropped + timed out) / scheduled for a sustained step.
    public static let maxLossRatio = 0.001
    /// Every server core's mean busy fraction must stay at or below this.
    public static let maxCoreBusy = 0.85
    public static let maxDiskAwaitMillis = 20.0
    public static let maxDiskQueueDepth = 4.0
    /// `$by_category` buffered events may grow by at most this fraction of the events written.
    public static let maxBufferedGrowthFraction = 0.01
}

/// Whether a step kept up with its target rate. Degenerate input (nothing scheduled, no measured time) is never sustained.
public func isSustained(_ r: OutcomeRecorder, targetRate: Double, measuredSeconds: Double, backlogGrew: Bool) -> Bool {
    isSustained(
        scheduled: r.scheduled, succeeded: r.succeeded, lost: r.failed + r.dropped + r.timedOut,
        targetRate: targetRate, measuredSeconds: measuredSeconds, backlogGrew: backlogGrew
    )
}

/// `isSustained(_:targetRate:measuredSeconds:backlogGrew:)` over stored counts (`lost` = failed + dropped + timed out).
public func isSustained(scheduled: Int, succeeded: Int, lost: Int, targetRate: Double, measuredSeconds: Double, backlogGrew: Bool) -> Bool {
    guard scheduled > 0, measuredSeconds > 0, measuredSeconds.isFinite, targetRate.isFinite, targetRate >= 0 else { return false }
    let successRate = Double(succeeded) / measuredSeconds
    let losses = Double(lost) / Double(scheduled)
    return successRate >= EvaluationThresholds.sustainedRateFraction * targetRate
        && losses <= EvaluationThresholds.maxLossRatio
        && !backlogGrew
}

/// Server-side resource readings over one step's measure window.
public struct HeadroomSample: Codable, Sendable {
    /// Mean busy fraction (0...1) per server core.
    public var coreBusy: [Double]
    public var diskAwaitMillis: Double
    public var diskQueueDepth: Double
    public var projectionBufferedStart: Int64
    public var projectionBufferedEnd: Int64
    public var eventsWritten: Int64

    public init(coreBusy: [Double], diskAwaitMillis: Double, diskQueueDepth: Double, projectionBufferedStart: Int64, projectionBufferedEnd: Int64, eventsWritten: Int64) {
        self.coreBusy = coreBusy
        self.diskAwaitMillis = diskAwaitMillis
        self.diskQueueDepth = diskQueueDepth
        self.projectionBufferedStart = projectionBufferedStart
        self.projectionBufferedEnd = projectionBufferedEnd
        self.eventsWritten = eventsWritten
    }
}

/// Whether the server had headroom. An empty `coreBusy` means no measurement and counts as no headroom, as does any NaN reading.
public func hasHeadroom(_ s: HeadroomSample) -> Bool {
    guard !s.coreBusy.isEmpty else { return false }
    let allowedGrowth = EvaluationThresholds.maxBufferedGrowthFraction * Double(max(s.eventsWritten, 0))
    return s.coreBusy.allSatisfy { $0 <= EvaluationThresholds.maxCoreBusy }
        && s.diskAwaitMillis <= EvaluationThresholds.maxDiskAwaitMillis
        && s.diskQueueDepth <= EvaluationThresholds.maxDiskQueueDepth
        && Double(s.projectionBufferedEnd - s.projectionBufferedStart) <= allowedGrowth
}
