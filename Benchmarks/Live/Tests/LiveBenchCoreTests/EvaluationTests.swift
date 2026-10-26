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

    @Test func degenerateInputsAreNotSustained() {
        #expect(!isSustained(OutcomeRecorder(), targetRate: 10, measuredSeconds: 1, backlogGrew: false))
        #expect(!isSustained(recorder(ok: 10), targetRate: 10, measuredSeconds: 0, backlogGrew: false))
        #expect(!isSustained(recorder(ok: 10), targetRate: 10, measuredSeconds: .nan, backlogGrew: false))
    }

    private func sample(cores: [Double] = [0.5], disk: Double = 1, queue: Double = 0.2, start: Int64 = 0, end: Int64 = 0, written: Int64 = 1000) -> HeadroomSample {
        .init(coreBusy: cores, diskAwaitMillis: disk, diskQueueDepth: queue, projectionBufferedStart: start, projectionBufferedEnd: end, eventsWritten: written)
    }

    @Test func singleSaturatedCoreFailsHeadroom() {
        #expect(!hasHeadroom(.init(coreBusy: [0.95, 0.30], diskAwaitMillis: 1, diskQueueDepth: 0.2, projectionBufferedStart: 0, projectionBufferedEnd: 0, eventsWritten: 1000)))
    }

    @Test func headroomBoundariesAreInclusive() {
        #expect(hasHeadroom(sample(cores: [0.85, 0.1], disk: 20, queue: 4, start: 5, end: 15, written: 1000)))
        #expect(!hasHeadroom(sample(disk: 20.1)))
        #expect(!hasHeadroom(sample(queue: 4.1)))
        #expect(!hasHeadroom(sample(start: 5, end: 16, written: 1000)))
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
