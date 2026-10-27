import Testing
@testable import LiveBenchCore

@Suite("Evaluation")
struct EvaluationTests {
    private func recorder(ok: Int, failed: Int = 0, dropped: Int = 0, timedOut: Int = 0) -> OutcomeRecorder {
        var r = OutcomeRecorder()
        for _ in 0..<ok { r.record(.success(latencyMicros: 100)) }
        for _ in 0..<failed { r.record(.failure) }
        for _ in 0..<dropped { r.record(.drop) }
        for _ in 0..<timedOut { r.record(.timeout) }
        return r
    }

    @Test func zeroSuccessStepIsNotSustainedAndHasNoNaN() {
        var r = OutcomeRecorder(); for _ in 0..<10 { r.record(.failure) }
        #expect(!isSustained(r, targetRate: 10, measuredSeconds: 1, backlogGrew: false))
    }

    @Test func healthyStepIsSustained() {
        #expect(isSustained(recorder(ok: 1000), targetRate: 100, measuredSeconds: 10, backlogGrew: false))
    }

    @Test func rateBelowNinetyNinePercentIsNotSustained() {
        #expect(!isSustained(recorder(ok: 980), targetRate: 100, measuredSeconds: 10, backlogGrew: false))
        #expect(isSustained(recorder(ok: 990, failed: 0), targetRate: 100, measuredSeconds: 10, backlogGrew: false))
    }

    @Test func lossRatioAndBacklogBreakSustained() {
        // 2 losses in 1002 scheduled is above 0.1%.
        #expect(!isSustained(recorder(ok: 1000, failed: 2), targetRate: 100, measuredSeconds: 10, backlogGrew: false))
        #expect(isSustained(recorder(ok: 1000, timedOut: 1), targetRate: 100, measuredSeconds: 10, backlogGrew: false))
        #expect(!isSustained(recorder(ok: 1000), targetRate: 100, measuredSeconds: 10, backlogGrew: true))
    }

    @Test func backlogGrowthBeyondOnePercentOfTheSecondHalfIsGrowth() {
        // 1000/s for 60 s: 30,000 in the second half, so 1% (300) beats the spike allowance (250).
        #expect(!backlogGrew(atMidpoint: 5, atEnd: 305, scheduledSecondHalf: 30_000, targetRate: 1000))
        #expect(backlogGrew(atMidpoint: 5, atEnd: 306, scheduledSecondHalf: 30_000, targetRate: 1000))
        #expect(!backlogGrew(atMidpoint: 305, atEnd: 5, scheduledSecondHalf: 30_000, targetRate: 1000))
    }

    @Test func clientCompletingTwoPercentShortIsGrown() {
        // 1000/s scheduled, 980/s completed: over the 30 s second half the backlog grows by about 20 × 30 = 600, twice
        // the tolerance of max(1, 300, 250). Every operation can still succeed within the deadline and the drain.
        #expect(backlogGrew(atMidpoint: 20, atEnd: 620, scheduledSecondHalf: 30_000, targetRate: 1000))
        #expect(BacklogSamples(atMidpoint: 20, atEnd: 620, scheduledSecondHalf: 30_000).grew(targetRate: 1000))
    }

    @Test func latencySpikeUnderOneSampleIsNotGrowthAtLowRates() {
        // 10/s for 30 s: 150 in the second half (1% is 1.5), the spike allowance is 2.5. A 200 ms spike under the end
        // sample leaves 3 outstanding instead of 1: not growth. A drift of 3 more is.
        #expect(!backlogGrew(atMidpoint: 1, atEnd: 3, scheduledSecondHalf: 150, targetRate: 10))
        #expect(backlogGrew(atMidpoint: 1, atEnd: 4, scheduledSecondHalf: 150, targetRate: 10))
        // 20/s: the allowance is exactly 5 operations, and growth must exceed it.
        #expect(!backlogGrew(atMidpoint: 0, atEnd: 5, scheduledSecondHalf: 300, targetRate: 20))
        #expect(backlogGrew(atMidpoint: 0, atEnd: 6, scheduledSecondHalf: 300, targetRate: 20))
    }

    @Test func backlogGrowthToleratesOneOperationAtTheLowestRates() {
        // 1/s (the cells' lowest rate) for 30 s: 1% of 15 is 0.15 and the allowance 0.25, so the minimum of one rules.
        #expect(!backlogGrew(atMidpoint: 0, atEnd: 1, scheduledSecondHalf: 15, targetRate: 1))
        #expect(backlogGrew(atMidpoint: 0, atEnd: 2, scheduledSecondHalf: 15, targetRate: 1))
        // A rate that is not a positive finite number adds no allowance.
        #expect(backlogGrew(atMidpoint: 0, atEnd: 2, scheduledSecondHalf: 15, targetRate: .nan))
        #expect(backlogGrew(atMidpoint: 0, atEnd: 2, scheduledSecondHalf: 15, targetRate: -100))
        #expect(OutcomeRecorder().backlog == nil)
    }

    @Test func degenerateInputsAreNotSustained() {
        #expect(!isSustained(OutcomeRecorder(), targetRate: 10, measuredSeconds: 1, backlogGrew: false))
        #expect(!isSustained(recorder(ok: 10), targetRate: 10, measuredSeconds: 0, backlogGrew: false))
        #expect(!isSustained(recorder(ok: 10), targetRate: 10, measuredSeconds: .nan, backlogGrew: false))
    }

    private func sample(cores: [Double] = [0.5], disk: Double = 1, queue: Double = 0.2, start: Int64 = 0, end: Int64 = 0, written: Int64 = 1000, catchUp: Double? = 0.4) -> HeadroomSample {
        .init(coreBusy: cores, diskAwaitMillis: disk, diskQueueDepth: queue, projectionBufferedStart: start, projectionBufferedEnd: end, eventsWritten: written, projectionCatchUpSeconds: catchUp)
    }

    @Test func singleSaturatedCoreFailsHeadroom() {
        #expect(!hasHeadroom(sample(cores: [0.95, 0.30])))
    }

    @Test func headroomBoundariesAreInclusive() {
        #expect(hasHeadroom(sample(cores: [0.85, 0.1], disk: 20, queue: 4, catchUp: 5)))
        #expect(!hasHeadroom(sample(disk: 20.1)))
        #expect(!hasHeadroom(sample(queue: 4.1)))
        #expect(!hasHeadroom(sample(catchUp: 5.01)))
    }

    /// The projection gate is the catch-up after the window, not `bufferedEvents`: that is `$by_category`'s read-ahead
    /// queue (bounded by its pending-events threshold), not its lag behind the log.
    @Test func projectionGateIsTheCatchUpAfterTheWindowNotTheBuffer() {
        #expect(hasHeadroom(sample(start: 0, end: 4_000, written: 1000, catchUp: 1.5)))
        #expect(!hasHeadroom(sample(start: 0, end: 0, catchUp: nil)))
    }

    @Test func emptyCoreMeasurementHasNoHeadroom() {
        #expect(!hasHeadroom(sample(cores: [])))
    }

    @Test func storedCountsJudgeLikeTheRecorder() {
        for (ok, lost) in [(1000, 0), (999, 1), (990, 10), (0, 10)] {
            let r = recorder(ok: ok, timedOut: lost)
            #expect(
                isSustained(scheduled: ok + lost, succeeded: ok, lost: lost, targetRate: 1000, measuredSeconds: 1, backlogGrew: false)
                    == isSustained(r, targetRate: 1000, measuredSeconds: 1, backlogGrew: false)
            )
        }
    }
}
