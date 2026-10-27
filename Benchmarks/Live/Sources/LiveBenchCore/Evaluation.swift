import Foundation

/// Fixed gate thresholds (see the spec's "Fixed initial parameters").
public enum EvaluationThresholds {
    /// A step is sustained when succeeded / measuredSeconds reaches this fraction of the target rate.
    public static let sustainedRateFraction = 0.99
    /// Maximum (failed + dropped + timed out) / scheduled for a sustained step.
    public static let maxLossRatio = 0.001
    /// The open loop's backlog grew when it rose from the window's midpoint to the end of scheduling by more than this
    /// fraction of the operations scheduled in the second half, or by more than `minBacklogGrowth`, whichever is
    /// larger. Growth beyond 1% of the second half's schedule means completions fell behind the target rate; one
    /// operation of tolerance absorbs sampling jitter at low rates (the sample can land just before or after a
    /// completion).
    public static let maxBacklogGrowthFraction = 0.01
    public static let minBacklogGrowth = 1
    /// Every server core's mean busy fraction must stay at or below this.
    public static let maxCoreBusy = 0.85
    public static let maxDiskAwaitMillis = 20.0
    public static let maxDiskQueueDepth = 4.0
    /// `$by_category` must have processed the last event written by the end of the measure window within this many
    /// seconds after it ends. (Its `bufferedEvents` is not a lag measure: it is the projection's read-ahead queue,
    /// whose reader pauses above `PendingEventsThreshold` and resumes below half of it, so it stays bounded however far
    /// the projection falls behind the log.)
    public static let maxProjectionCatchUpSeconds = 5.0
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

/// Whether the open loop's backlog grew over the second half of the window: `atEnd - atMidpoint` exceeds
/// `max(minBacklogGrowth, maxBacklogGrowthFraction * scheduledSecondHalf)`. A client that completes slightly slower
/// than the target rate can still finish everything within the deadline and the drain; this is what catches it. Callers
/// without samples (ghz, older results, a loop cancelled before its midpoint) pass `backlogGrew: false` to
/// `isSustained`: unknown is not growth.
public func backlogGrew(atMidpoint: Int, atEnd: Int, scheduledSecondHalf: Int) -> Bool {
    let tolerance = max(
        Double(EvaluationThresholds.minBacklogGrowth),
        EvaluationThresholds.maxBacklogGrowthFraction * Double(scheduledSecondHalf)
    )
    return Double(atEnd - atMidpoint) > tolerance
}

/// Server-side resource readings over one step's measure window.
public struct HeadroomSample: Codable, Sendable {
    /// Mean busy fraction (0...1) per server core.
    public var coreBusy: [Double]
    public var diskAwaitMillis: Double
    public var diskQueueDepth: Double
    /// `$by_category`'s `bufferedEvents` (its read-ahead queue) at the start and end of the window; informational.
    public var projectionBufferedStart: Int64
    public var projectionBufferedEnd: Int64
    public var eventsWritten: Int64
    /// Seconds after the measure window ended until `$by_category` had processed the last event written by then; nil
    /// when it had not within `EvaluationThresholds.maxProjectionCatchUpSeconds` (the gate fails).
    public var projectionCatchUpSeconds: Double?

    public init(
        coreBusy: [Double], diskAwaitMillis: Double, diskQueueDepth: Double, projectionBufferedStart: Int64, projectionBufferedEnd: Int64,
        eventsWritten: Int64, projectionCatchUpSeconds: Double?
    ) {
        self.coreBusy = coreBusy
        self.diskAwaitMillis = diskAwaitMillis
        self.diskQueueDepth = diskQueueDepth
        self.projectionBufferedStart = projectionBufferedStart
        self.projectionBufferedEnd = projectionBufferedEnd
        self.eventsWritten = eventsWritten
        self.projectionCatchUpSeconds = projectionCatchUpSeconds
    }
}

/// Whether the server had headroom. An empty `coreBusy` means no measurement and counts as no headroom, as does any NaN
/// reading and a projection that did not catch up after the window.
public func hasHeadroom(_ s: HeadroomSample) -> Bool {
    guard !s.coreBusy.isEmpty, let catchUp = s.projectionCatchUpSeconds else { return false }
    return s.coreBusy.allSatisfy { $0 <= EvaluationThresholds.maxCoreBusy }
        && s.diskAwaitMillis <= EvaluationThresholds.maxDiskAwaitMillis
        && s.diskQueueDepth <= EvaluationThresholds.maxDiskQueueDepth
        && catchUp <= EvaluationThresholds.maxProjectionCatchUpSeconds
}
