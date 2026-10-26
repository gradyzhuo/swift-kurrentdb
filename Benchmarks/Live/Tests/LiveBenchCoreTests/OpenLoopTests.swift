import Foundation
import Synchronization
import Testing
@testable import LiveBenchCore

/// Every scheduled index must produce exactly one outcome.
private func expectAccounted(_ r: OutcomeRecorder, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(r.scheduled == r.succeeded + r.failed + r.dropped + r.timedOut, sourceLocation: sourceLocation)
}

/// Waits without honouring cancellation, like a client call that ignores `Task.cancel()`.
private func uncancellableSleep(seconds: Double) async {
    await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { c.resume() }
    }
}

private func elapsedSeconds(since start: ContinuousClock.Instant) -> Double {
    let d = start.duration(to: .now)
    return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
}

@Suite("OpenLoop", .serialized)
struct OpenLoopTests {
    @Test func stalledOperationDelaysAreMeasuredFromSchedule() async {
        // 100 ops/s for 0.5 s; op #2 stalls 200 ms. Later ops must still be scheduled on time.
        let started = Mutex<[Int: ContinuousClock.Instant]>([:])
        let t0 = ContinuousClock.now
        let r = await runOpenLoop(.init(rate: 100, duration: .milliseconds(500), inFlightCap: 256, deadline: .seconds(1), drain: .milliseconds(300))) { i in
            started.withLock { $0[i] = .now }
            if i == 2 { try await Task.sleep(for: .milliseconds(200)) }
        }
        #expect(r.scheduled == 50)
        #expect(r.succeeded == 50)
        #expect(r.histogram.valueAtPercentile(100) >= 200_000)
        expectAccounted(r)
        // Op #3 is due at 30 ms; it must not wait behind op #2's 200 ms stall (generous slack for loaded CI).
        let op3 = started.withLock { $0[3] }
        #expect(op3.map { t0.duration(to: $0) < .milliseconds(180) } == true)
    }

    @Test func capProducesDropsNotBackpressure() async {
        let r = await runOpenLoop(.init(rate: 200, duration: .milliseconds(200), inFlightCap: 2, deadline: .seconds(2), drain: .seconds(1))) { _ in
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(r.dropped > 0)
        #expect(r.scheduled == 40)
        #expect(r.succeeded > 0)
        expectAccounted(r)
    }

    @Test func unfinishedAfterDrainCountAsTimeouts() async {
        let t0 = ContinuousClock.now
        let r = await runOpenLoop(.init(rate: 10, duration: .milliseconds(100), inFlightCap: 10, deadline: .seconds(10), drain: .milliseconds(50))) { _ in
            try await Task.sleep(for: .seconds(5))
        }
        #expect(r.scheduled == 1)
        #expect(r.timedOut == r.scheduled)
        #expect(elapsedSeconds(since: t0) < 2)
        expectAccounted(r)
    }

    @Test func throwingOperationIsAFailure() async {
        struct E: Error {}
        let r = await runOpenLoop(.init(rate: 50, duration: .milliseconds(100), inFlightCap: 10, deadline: .seconds(1), drain: .milliseconds(100))) { _ in throw E() }
        #expect(r.scheduled == 5)
        #expect(r.failed == r.scheduled)
        expectAccounted(r)
    }

    @Test func deadlineIsEnforcedEvenWhenOperationIgnoresCancellation() async {
        let t0 = ContinuousClock.now
        let r = await runOpenLoop(.init(rate: 20, duration: .milliseconds(100), inFlightCap: 10, deadline: .milliseconds(100), drain: .seconds(5))) { _ in
            await uncancellableSleep(seconds: 3)
        }
        #expect(r.scheduled == 2)
        #expect(r.timedOut == r.scheduled)
        // Both deadlines expire by ~0.15 s; the run must not wait for the 3 s operations.
        #expect(elapsedSeconds(since: t0) < 2)
        expectAccounted(r)
    }

    @Test func drainReturnsPromptlyWhenOperationIgnoresCancellation() async {
        let t0 = ContinuousClock.now
        let r = await runOpenLoop(.init(rate: 20, duration: .milliseconds(100), inFlightCap: 10, deadline: .seconds(10), drain: .milliseconds(100))) { _ in
            await uncancellableSleep(seconds: 3)
        }
        #expect(r.scheduled == 2)
        #expect(r.timedOut == r.scheduled)
        #expect(elapsedSeconds(since: t0) < 2)
        expectAccounted(r)
    }

    @Test func timedOutOperationIsCancelled() async {
        let sawCancellation = Mutex(false)
        let r = await runOpenLoop(.init(rate: 10, duration: .milliseconds(100), inFlightCap: 10, deadline: .milliseconds(50), drain: .seconds(2))) { _ in
            do { try await Task.sleep(for: .seconds(5)) } catch { sawCancellation.withLock { $0 = true } ; throw error }
        }
        #expect(r.timedOut == 1)
        #expect(r.failed == 0) // the late CancellationError must not be recorded a second time
        #expect(sawCancellation.withLock { $0 })
        expectAccounted(r)
    }

    @Test func returnsAsSoonAsEverythingCompletes() async {
        let t0 = ContinuousClock.now
        let r = await runOpenLoop(.init(rate: 100, duration: .milliseconds(100), inFlightCap: 10, deadline: .seconds(5), drain: .seconds(5))) { _ in
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(r.scheduled == 10)
        #expect(r.succeeded == 10)
        #expect(r.histogram.valueAtPercentile(0) >= 10_000)
        // Drain is an upper bound, not a fixed wait.
        #expect(elapsedSeconds(since: t0) < 2)
        expectAccounted(r)
    }

    @Test func fractionalScheduleCount() async {
        // 30 ops/s for 0.1 s: offsets 0, 33.3, 66.7 ms are before the end; 100 ms is not.
        let r = await runOpenLoop(.init(rate: 30, duration: .milliseconds(100), inFlightCap: 10, deadline: .seconds(1), drain: .milliseconds(200))) { _ in }
        #expect(r.scheduled == 3)
        #expect(r.succeeded == 3)
        expectAccounted(r)
    }
}
