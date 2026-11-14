import Testing
import Foundation
@testable import LiveBenchCore

@Suite("Statistics")
struct StatisticsTests {
    @Test func throughputHalfSpeedMisses() {
        let pairs = (0..<5).map { _ in RoundPair(swift: 500, dotnet: 1000) }
        let (e, v) = estimateRatio(pairs, direction: .higherIsBetter, minimumRounds: 5)
        #expect(abs(e!.point - 2.0) < 1e-9); #expect(v == .misses)
    }

    @Test func intervalStraddlingTargetIsInconclusive() {
        let ratios = [0.98, 1.05, 1.14, 1.25, 1.33]
        let pairs = ratios.map { RoundPair(swift: $0, dotnet: 1) }
        #expect(estimateRatio(pairs, direction: .lowerIsBetter, minimumRounds: 5).1 == .inconclusive)
    }

    @Test func tightIntervalBelowTargetMeets() {
        let pairs = [1.05, 1.07, 1.08, 1.09, 1.10].map { RoundPair(swift: $0, dotnet: 1) }
        #expect(estimateRatio(pairs, direction: .lowerIsBetter, minimumRounds: 5).1 == .meets)
    }

    @Test func unpairedRoundsAreDroppedNotMixed() {
        let pairs = [RoundPair(swift: 1.1, dotnet: 1), RoundPair(swift: nil, dotnet: 1), RoundPair(swift: 1.0, dotnet: nil)]
            + Array(repeating: RoundPair(swift: 1.1, dotnet: 1), count: 3)
        let (e, v) = estimateRatio(pairs, direction: .lowerIsBetter, minimumRounds: 5)
        #expect(e?.rounds == 4); #expect(v == .insufficientRounds)
    }

    @Test func fewerThanTwoPairsHasNoEstimate() {
        let (e, v) = estimateRatio([RoundPair(swift: 1, dotnet: 1)], direction: .lowerIsBetter, minimumRounds: 1)
        #expect(e == nil); #expect(v == .insufficientRounds)
        let (e0, v0) = estimateRatio([], direction: .lowerIsBetter, minimumRounds: 5)
        #expect(e0 == nil); #expect(v0 == .insufficientRounds)
    }

    @Test func nonPositiveOrNonFiniteValuesDropThePair() {
        let bad = [RoundPair(swift: 0, dotnet: 1), RoundPair(swift: 1, dotnet: -1), RoundPair(swift: .nan, dotnet: 1), RoundPair(swift: 1, dotnet: .infinity)]
        let pairs = bad + Array(repeating: RoundPair(swift: 1.0, dotnet: 1), count: 3)
        let (e, v) = estimateRatio(pairs, direction: .lowerIsBetter, minimumRounds: 3)
        #expect(e?.rounds == 3); #expect(v == .meets)
        #expect(e!.point.isFinite && e!.lower.isFinite && e!.upper.isFinite)
    }

    @Test func intervalMatchesStudentT() {
        // log-ratios of 1, 2, 3 (as e^x): mean 2, sd 1, n 3, t(2) = 4.303.
        let pairs = [1.0, 2.0, 3.0].map { RoundPair(swift: exp($0), dotnet: 1) }
        let e = estimateRatio(pairs, direction: .lowerIsBetter, minimumRounds: 3).0!
        let half = 4.303 / 3.0.squareRoot()
        #expect(abs(log(e.point) - 2) < 1e-9)
        #expect(abs(log(e.lower) - (2 - half)) < 1e-9)
        #expect(abs(log(e.upper) - (2 + half)) < 1e-9)
    }

    /// Spec: meets when the upper bound ≤ 1.2, misses when the lower bound > 1.2.
    @Test func verdictBoundaryAtTheTargetIsInclusiveForMeets() {
        #expect(verdict(for: RatioEstimate(point: 1.1, lower: 1.0, upper: 1.2, rounds: 5), minimumRounds: 5) == .meets)
        #expect(verdict(for: RatioEstimate(point: 1.25, lower: 1.2, upper: 1.3, rounds: 5), minimumRounds: 5) == .inconclusive)
        #expect(verdict(for: RatioEstimate(point: 1.3, lower: 1.2000001, upper: 1.4, rounds: 5), minimumRounds: 5) == .misses)
        #expect(verdict(for: RatioEstimate(point: 1.1, lower: 1.0, upper: 1.2, rounds: 4), minimumRounds: 5) == .insufficientRounds)
    }

    @Test func criticalValueTable() {
        #expect(studentT975(degreesOfFreedom: 1) == 12.706)
        #expect(studentT975(degreesOfFreedom: 30) == 2.042)
        #expect(studentT975(degreesOfFreedom: 31) == 1.96)
    }
}
