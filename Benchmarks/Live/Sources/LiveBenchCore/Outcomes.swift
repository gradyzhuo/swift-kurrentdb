import Foundation
import Histogram

/// The result of one scheduled operation attempt.
public enum Outcome: Sendable {
    case success(latencyMicros: UInt64)
    case failure
    case drop
    case timeout
}

/// The open loop's backlog (operations launched with no recorded outcome yet; drops are not backlog), sampled at the
/// window's midpoint and at the end of scheduling. See `runOpenLoop`.
public struct BacklogSamples: Equatable, Sendable {
    /// Backlog right after the first index scheduled at or after half the window was launched (or dropped).
    public var atMidpoint: Int
    /// Backlog when the scheduling loop exits, before the drain.
    public var atEnd: Int
    /// Indices scheduled from the midpoint index to the last one, both included.
    public var scheduledSecondHalf: Int

    public init(atMidpoint: Int, atEnd: Int, scheduledSecondHalf: Int) {
        self.atMidpoint = atMidpoint
        self.atEnd = atEnd
        self.scheduledSecondHalf = scheduledSecondHalf
    }

    /// `backlogGrew(atMidpoint:atEnd:scheduledSecondHalf:)` over these samples.
    public var grew: Bool {
        backlogGrew(atMidpoint: atMidpoint, atEnd: atEnd, scheduledSecondHalf: scheduledSecondHalf)
    }
}

/// Counts every scheduled attempt and keeps a latency histogram of the successes only.
public struct OutcomeRecorder: Sendable {
    public private(set) var succeeded = 0
    public private(set) var failed = 0
    public private(set) var dropped = 0
    public private(set) var timedOut = 0
    public private(set) var histogram: Histogram<UInt64>
    /// Set by `runOpenLoop` once its schedule reached the window's midpoint; nil otherwise.
    public internal(set) var backlog: BacklogSamples?

    /// Latencies from 1 us to 60 s with 3 significant digits.
    public init() {
        histogram = Histogram<UInt64>(lowestDiscernibleValue: 1, highestTrackableValue: 60_000_000, numberOfSignificantValueDigits: .three)
    }

    public var scheduled: Int { succeeded + failed + dropped + timedOut }

    public mutating func record(_ outcome: Outcome) {
        switch outcome {
        case .success(let micros):
            succeeded += 1
            _ = histogram.record(min(max(micros, 1), 60_000_000))
        case .failure: failed += 1
        case .drop: dropped += 1
        case .timeout: timedOut += 1
        }
    }
}

/// A latency percentile, or `.censored` when the rank falls among attempts that never succeeded (rendered "> deadline").
public enum PercentileValue: Codable, Equatable, Sendable {
    case micros(UInt64)
    case censored
}

/// Percentile ranked over all scheduled attempts; failures, drops and timeouts rank as +infinity.
public func percentile(_ p: Double, of r: OutcomeRecorder) -> PercentileValue {
    percentile(p, successes: r.histogram, scheduled: r.scheduled)
}

/// `percentile(_:of:)` over a stored trial: `successes` holds the latencies of the successes (its count is the number
/// of successes) and `scheduled` counts every attempt.
public func percentile(_ p: Double, successes: Histogram<UInt64>, scheduled: Int) -> PercentileValue {
    let succeeded = Int(successes.totalCount)
    guard scheduled > 0, succeeded > 0, p.isFinite else { return .censored }
    let clamped = min(max(p, 0), 100)
    // The small epsilon keeps exact ranks (e.g. 99.9% of 10,000) from rounding up on floating-point noise.
    let rank = max(1, Int((clamped / 100 * Double(scheduled) - 1e-9).rounded(.up)))
    if rank > succeeded { return .censored }
    return .micros(successes.valueAtPercentile(Double(rank) / Double(succeeded) * 100))
}
