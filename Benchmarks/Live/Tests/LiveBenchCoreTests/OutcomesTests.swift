import Foundation
import Testing
@testable import LiveBenchCore

@Suite("Outcomes")
struct OutcomesTests {
    @Test func censoredWhenRankFallsInLosses() {
        var r = OutcomeRecorder()
        for i in 0..<9_995 { r.record(.success(latencyMicros: UInt64(1_000 + i))) }
        for _ in 0..<3 { r.record(.timeout) }
        for _ in 0..<2 { r.record(.drop) }
        #expect(r.scheduled == 10_000)
        #expect(r.timedOut == 3)
        #expect(r.dropped == 2)
        #expect(percentile(99.9, of: r) != .censored)
        #expect(percentile(99.99, of: r) == .censored)
    }

    @Test func allFailedStepHasNoNumbers() {
        var r = OutcomeRecorder()
        for _ in 0..<100 { r.record(.failure) }
        #expect(percentile(50, of: r) == .censored)
        #expect(r.succeeded == 0)
        #expect(r.failed == 100)
    }

    @Test func emptyRecorderIsCensoredNotCrashing() {
        let r = OutcomeRecorder()
        #expect(r.scheduled == 0)
        #expect(percentile(50, of: r) == .censored)
        #expect(percentile(100, of: r) == .censored)
    }

    @Test func allSucceededReturnsMicros() {
        var r = OutcomeRecorder()
        for i in 1...100 { r.record(.success(latencyMicros: UInt64(i * 100))) }
        guard case .micros(let v) = percentile(50, of: r) else {
            Issue.record("expected micros"); return
        }
        #expect(v >= 4_900 && v <= 5_100)
        #expect(percentile(100, of: r) != .censored)
    }

    @Test func histogramFileRoundTrips() throws {
        var r = OutcomeRecorder()
        [5, 50, 500, 5_000].forEach { r.record(.success(latencyMicros: $0)) }
        let file = HistogramFile(r.histogram)
        #expect(file.unit == "us")
        let back = try JSONDecoder().decode(HistogramFile.self, from: JSONEncoder().encode(file)).histogram()
        #expect(back.totalCount == 4)
        #expect(back.valueAtPercentile(100) == r.histogram.valueAtPercentile(100))
    }

    @Test func percentileValueCodableRoundTrips() throws {
        for v in [PercentileValue.micros(1234), .censored] {
            let back = try JSONDecoder().decode(PercentileValue.self, from: JSONEncoder().encode(v))
            #expect(back == v)
        }
    }

    @Test func storedHistogramRanksLikeTheRecorder() {
        var r = OutcomeRecorder()
        for i in 1...990 { r.record(.success(latencyMicros: UInt64(i))) }
        for _ in 0..<10 { r.record(.timeout) }
        let stored = HistogramFile(r.histogram).histogram()
        for p in [50.0, 99.0, 99.5] {
            #expect(percentile(p, successes: stored, scheduled: r.scheduled) == percentile(p, of: r))
        }
        #expect(percentile(99.5, successes: stored, scheduled: r.scheduled) == .censored)
        #expect(percentile(50, successes: HistogramFile(buckets: []).histogram(), scheduled: 0) == .censored)
    }
}
