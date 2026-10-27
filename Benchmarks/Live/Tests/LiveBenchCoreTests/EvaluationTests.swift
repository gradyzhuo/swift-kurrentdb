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
        // 1,000 indices in the second half: up to 10 more outstanding at the end is tolerated.
        #expect(!backlogGrew(atMidpoint: 5, atEnd: 15, scheduledSecondHalf: 1000, inFlightAtP99: 0))
        #expect(backlogGrew(atMidpoint: 5, atEnd: 16, scheduledSecondHalf: 1000, inFlightAtP99: 0))
        #expect(!backlogGrew(atMidpoint: 15, atEnd: 5, scheduledSecondHalf: 1000, inFlightAtP99: 0))
    }

    @Test func backlogGrowthToleratesOneOperationAtLowCounts() {
        // 10 indices in the second half: 1% is 0.1, so the one-operation minimum applies.
        #expect(!backlogGrew(atMidpoint: 0, atEnd: 1, scheduledSecondHalf: 10, inFlightAtP99: 0))
        #expect(backlogGrew(atMidpoint: 0, atEnd: 2, scheduledSecondHalf: 10, inFlightAtP99: 0))
        #expect(!backlogGrew(atMidpoint: 3, atEnd: 4, scheduledSecondHalf: 150, inFlightAtP99: 0))
        #expect(backlogGrew(atMidpoint: 3, atEnd: 5, scheduledSecondHalf: 150, inFlightAtP99: 0))
        #expect(BacklogSamples(atMidpoint: 0, atEnd: 2, scheduledSecondHalf: 10).grew(inFlightAtP99: 0))
        #expect(OutcomeRecorder().backlog == nil)
    }

    @Test func latencySpikeUnderOneSampleIsNotGrowthAtLowRates() {
        // 10/s for 30 s (150 in the second half, 1% is 1.5): a 200 ms spike under the end sample leaves 3 outstanding
        // instead of 1. With a p99 of 200 ms, rate × p99 = 2 operations explain it.
        let at10 = inFlight(targetRate: 10, p99: .micros(200_000))
        #expect(at10 == 2)
        #expect(!backlogGrew(atMidpoint: 1, atEnd: 3, scheduledSecondHalf: 150, inFlightAtP99: at10))
        // A drift of 3 more outstanding is beyond what one p99 explains.
        #expect(backlogGrew(atMidpoint: 1, atEnd: 4, scheduledSecondHalf: 150, inFlightAtP99: at10))
        // 1/s (the cells' lowest rate) for 30 s: 15 in the second half, so only the one-operation minimum and the
        // p99 term apply. A 2.5 s p99 explains 2 more outstanding, not 3.
        let at1 = inFlight(targetRate: 1, p99: .micros(2_500_000))
        #expect(!backlogGrew(atMidpoint: 0, atEnd: 2, scheduledSecondHalf: 15, inFlightAtP99: at1))
        #expect(backlogGrew(atMidpoint: 0, atEnd: 3, scheduledSecondHalf: 15, inFlightAtP99: at1))
    }

    @Test func censoredOrInvalidP99AddsNoTolerance() {
        #expect(inFlight(targetRate: 10, p99: .censored) == 0)
        #expect(inFlight(targetRate: .nan, p99: .micros(1_000_000)) == 0)
        #expect(inFlight(targetRate: 0, p99: .micros(1_000_000)) == 0)
        #expect(backlogGrew(atMidpoint: 0, atEnd: 2, scheduledSecondHalf: 15, inFlightAtP99: .infinity))
        #expect(backlogGrew(atMidpoint: 0, atEnd: 2, scheduledSecondHalf: 15, inFlightAtP99: .nan))
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
