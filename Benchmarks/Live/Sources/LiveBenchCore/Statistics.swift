import Foundation

/// Whether a smaller or a larger measurement is better.
public enum Direction: Sendable {
    case lowerIsBetter, higherIsBetter
}

/// One round's measurement from each client; a nil side means that client produced no data that round.
public struct RoundPair: Sendable {
    public var swift: Double?
    public var dotnet: Double?
    public init(swift: Double?, dotnet: Double?) {
        self.swift = swift
        self.dotnet = dotnet
    }
}

/// Swift-to-.NET ratio oriented so that higher means Swift is worse, with a 95% confidence interval.
public struct RatioEstimate: Codable, Sendable {
    public var point: Double
    public var lower: Double
    public var upper: Double
    public var rounds: Int
    public init(point: Double, lower: Double, upper: Double, rounds: Int) {
        self.point = point
        self.lower = lower
        self.upper = upper
        self.rounds = rounds
    }
}

public enum Verdict: String, Codable, Sendable {
    case meets, misses, inconclusive, insufficientRounds
}

/// The ratio Swift must stay under to meet the goal.
public let targetRatio = 1.2

/// Two-sided 95% Student t critical values for df 1...30; index 0 is df 1.
public let studentT975Table: [Double] = [
    12.706, 4.303, 3.182, 2.776, 2.571, 2.447, 2.365, 2.306, 2.262, 2.228,
    2.201, 2.179, 2.160, 2.145, 2.131, 2.120, 2.110, 2.101, 2.093, 2.086,
    2.080, 2.074, 2.069, 2.064, 2.060, 2.056, 2.052, 2.048, 2.045, 2.042,
]

/// Critical value for the given degrees of freedom; the normal 1.96 beyond the table.
public func studentT975(degreesOfFreedom df: Int) -> Double {
    guard df >= 1 else { return .nan }
    return df <= studentT975Table.count ? studentT975Table[df - 1] : 1.96
}

/// Paired log-ratio estimate with a Student t interval. Pairs with a missing, non-positive or non-finite side are dropped.
/// Fewer than two usable pairs gives no estimate; fewer than `minimumRounds` gives an estimate (for display) but `.insufficientRounds`.
public func estimateRatio(_ pairs: [RoundPair], direction: Direction, minimumRounds: Int) -> (RatioEstimate?, Verdict) {
    var logs: [Double] = []
    for p in pairs {
        guard let s = p.swift, let d = p.dotnet, s.isFinite, d.isFinite, s > 0, d > 0 else { continue }
        let ratio = direction == .lowerIsBetter ? s / d : d / s
        let l = log(ratio)
        guard l.isFinite else { continue }
        logs.append(l)
    }
    let n = logs.count
    guard n >= 2 else { return (nil, .insufficientRounds) }
    let mean = logs.reduce(0, +) / Double(n)
    let variance = logs.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(n - 1)
    let half = studentT975(degreesOfFreedom: n - 1) * variance.squareRoot() / Double(n).squareRoot()
    let estimate = RatioEstimate(point: exp(mean), lower: exp(mean - half), upper: exp(mean + half), rounds: n)
    guard estimate.point.isFinite, estimate.lower.isFinite, estimate.upper.isFinite, estimate.lower > 0 else {
        return (nil, .insufficientRounds)
    }
    return (estimate, verdict(for: estimate, minimumRounds: minimumRounds))
}

/// The verdict of an estimate against `targetRatio` (spec): fewer rounds than `minimumRounds` is `.insufficientRounds`;
/// otherwise `.meets` when the upper bound is ≤ the target, `.misses` when the lower bound is > it, else `.inconclusive`.
public func verdict(for estimate: RatioEstimate, minimumRounds: Int) -> Verdict {
    if estimate.rounds < minimumRounds { return .insufficientRounds }
    if estimate.upper <= targetRatio { return .meets }
    if estimate.lower > targetRatio { return .misses }
    return .inconclusive
}
