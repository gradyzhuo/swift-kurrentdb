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
        // 100 ops/s for 0.5 s; op #2 stalls 1 s. Later ops must still be scheduled on time. The deadline and drain are
        // far above anything a loaded host adds (the drain ends as soon as everything is accounted for), and op #3's
        // bound is far below the stall, so host load cannot flip either check.
        let started = Mutex<[Int: ContinuousClock.Instant]>([:])
        let t0 = ContinuousClock.now
        let r = await runOpenLoop(.init(rate: 100, duration: .milliseconds(500), inFlightCap: 256, deadline: .seconds(5), drain: .seconds(5))) { i in
            started.withLock { $0[i] = .now }
            if i == 2 { try await Task.sleep(for: .seconds(1)) }
        }
        #expect(r.scheduled == 50)
        #expect(r.succeeded == 50)
        #expect(r.histogram.valueAtPercentile(100) >= 1_000_000)
        expectAccounted(r)
        // Op #3 is due at 30 ms; it must not wait behind op #2's 1 s stall.
        let op3 = started.withLock { $0[3] }
        #expect(op3.map { t0.duration(to: $0) < .milliseconds(700) } == true)
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
        // The op's catch runs a few task hops after runOpenLoop returns; poll for up to 1 s.
        let t0 = ContinuousClock.now
        while !sawCancellation.withLock({ $0 }), t0.duration(to: .now) < .seconds(1) {
            try? await Task.sleep(for: .milliseconds(5))
        }
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

    @Test func completionPastDeadlineIsATimeoutEvenIfTheDeadlineTimerHasNotFired() async {
        // The clock's `now` jumps 10 s forward inside the operation, while its sleeps (and so the 1 s deadline timer)
        // run in real time. The operation therefore completes 10 s after its scheduled instant before the deadline
        // child can record anything. That is the race where a late completion could be recorded as a success.
        let clock = SkewedClock()
        let r = await runOpenLoop(.init(rate: 10, duration: .milliseconds(100), inFlightCap: 10, deadline: .seconds(1), drain: .seconds(2)), clock: clock) { _ in
            clock.skip(.seconds(10))
        }
        #expect(r.scheduled == 1)
        #expect(r.timedOut == 1)
        #expect(r.succeeded == 0)
        expectAccounted(r)
    }

    @Test func lateLaunchIsChargedFromTheSchedule() async {
        // Every sleep on this clock returns 50 ms late, so op #1 (due at 100 ms) launches about 50 ms late. Measuring
        // from the launch would hide that lag (coordinated omission); it must be charged from the schedule.
        let r = await runOpenLoop(.init(rate: 10, duration: .milliseconds(200), inFlightCap: 10, deadline: .seconds(2), drain: .seconds(1)), clock: OffsetSleepClock(offset: .milliseconds(50))) { _ in }
        #expect(r.scheduled == 2)
        #expect(r.succeeded == 2)
        #expect(r.histogram.valueAtPercentile(100) >= 45_000)
        expectAccounted(r)
    }

    @Test func earlyLaunchIsChargedFromTheLaunch() async {
        // Every sleep on this clock returns 20 ms early, so op #1 (due at 100 ms) launches about 20 ms early. Each op
        // takes 30 ms; measuring from the due instant would report about 10 ms for op #1, from the launch at least 30 ms.
        let r = await runOpenLoop(.init(rate: 10, duration: .milliseconds(200), inFlightCap: 10, deadline: .seconds(2), drain: .seconds(1)), clock: OffsetSleepClock(offset: .milliseconds(-20))) { _ in
            try await Task.sleep(for: .milliseconds(30))
        }
        #expect(r.scheduled == 2)
        #expect(r.succeeded == 2)
        #expect(r.histogram.valueAtPercentile(0) >= 29_000)
        expectAccounted(r)
    }

    /// Harness floor: latency of a no-op operation, i.e. what the scheduler itself adds to every measurement.
    /// Bounds are deliberately loose (debug build, loaded CI); the printed numbers are what to compare against the
    /// .NET driver's floor. A release build on an Apple Silicon Mac measures p50 / p99 of 4-7 / 150-190 µs at 1000/s and
    /// 6-7 / 126-380 µs at 8000/s.
    @Test(arguments: [1000.0, 8000.0])
    func noOpCalibrationFloor(rate: Double) async {
        let r = await runOpenLoop(.init(rate: rate, duration: .milliseconds(500), inFlightCap: 256, deadline: .seconds(5), drain: .seconds(1))) { _ in }
        let p50 = r.histogram.valueAtPercentile(50)
        let p99 = r.histogram.valueAtPercentile(99)
        print("open-loop harness floor at \(Int(rate))/s: p50 \(p50) µs, p99 \(p99) µs over \(r.succeeded) no-op operations")
        #expect(r.scheduled == Int(rate / 2))
        #expect(r.succeeded == r.scheduled)
        #expect(p50 < 2_000)
        #expect(p99 < 20_000)
        expectAccounted(r)
    }

    @Test func returnedCompletionInstantEndsTheLatency() async {
        // The operation reports that it completed 5 ms after its scheduled instant, then keeps running for 100 ms: the
        // latency must end at the reported instant, not when the operation returns.
        let clock = ContinuousClock()
        let start = clock.now
        let r = await runOpenLoop(.init(rate: 10, duration: .milliseconds(100), inFlightCap: 10, deadline: .seconds(2), drain: .seconds(1)), clock: clock) { _ -> ContinuousClock.Instant? in
            let completed = start.advanced(by: .milliseconds(5))
            try await Task.sleep(for: .milliseconds(100))
            return completed
        }
        #expect(r.succeeded == 1)
        #expect(r.histogram.valueAtPercentile(100) < 50_000)
        expectAccounted(r)
    }

    @Test func nilCompletionInstantMeansNow() async {
        let r = await runOpenLoop(.init(rate: 10, duration: .milliseconds(100), inFlightCap: 10, deadline: .seconds(2), drain: .seconds(1)), clock: ContinuousClock()) { _ -> ContinuousClock.Instant? in
            try await Task.sleep(for: .milliseconds(100))
            return nil
        }
        #expect(r.succeeded == 1)
        #expect(r.histogram.valueAtPercentile(0) >= 95_000)
        expectAccounted(r)
    }

    @Test func returnedInstantAtOrPastTheDeadlineIsATimeout() async {
        let clock = ContinuousClock()
        let start = clock.now
        let r = await runOpenLoop(.init(rate: 10, duration: .milliseconds(100), inFlightCap: 10, deadline: .milliseconds(500), drain: .seconds(1)), clock: clock) { _ -> ContinuousClock.Instant? in
            start.advanced(by: .seconds(1))
        }
        #expect(r.timedOut == 1)
        #expect(r.succeeded == 0)
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

/// A clock whose `now` can be pushed forward while its sleeps keep running in real time.
private final class SkewedClock: Clock, Sendable {
    typealias Instant = ContinuousClock.Instant
    private let base = ContinuousClock()
    private let skew = Mutex(Duration.zero)

    var now: Instant { base.now.advanced(by: skew.withLock { $0 }) }
    var minimumResolution: Duration { base.minimumResolution }

    func skip(_ d: Duration) { skew.withLock { $0 += d } }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try await base.sleep(until: deadline, tolerance: tolerance)
    }
}

/// A real-time clock whose sleeps all end `offset` after (or, if negative, before) the requested instant.
private struct OffsetSleepClock: Clock {
    typealias Instant = ContinuousClock.Instant
    let offset: Duration
    private let base = ContinuousClock()

    init(offset: Duration) { self.offset = offset }

    var now: Instant { base.now }
    var minimumResolution: Duration { base.minimumResolution }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try await base.sleep(until: deadline.advanced(by: offset), tolerance: tolerance)
    }
}
