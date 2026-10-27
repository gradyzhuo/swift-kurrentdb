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

    @Test func serializedOperationGrowsTheBacklog() async throws {
        // 50 ops/s for 0.4 s, each holding one shared resource for 50 ms: completions run at 20/s. Every operation
        // still succeeds within the deadline and the drain, so only the backlog shows the client falling behind. The
        // spans are 0.2 s: the midpoint span (indices 0-10) has its minimum at index 0 (1), the end span (indices
        // 10-19) at index 10, by when about 4 have completed (about 7). A loaded host only completes fewer, which
        // raises the end minimum more.
        let tail = Mutex<Task<Void, Never>?>(nil)
        let config = OpenLoopConfig(
            rate: 50, duration: .milliseconds(400), inFlightCap: 256, deadline: .seconds(10), drain: .seconds(5)
        )
        let r = await runOpenLoop(config) { _ in
            let mine = tail.withLock { previous in
                let next = Task { [previous] in
                    await previous?.value
                    try? await Task.sleep(for: .milliseconds(50))
                }
                previous = next
                return next
            }
            await mine.value
        }
        #expect(r.scheduled == 20)
        #expect(r.succeeded == 20)
        let backlog = try #require(r.backlog)
        #expect(backlog.scheduledSecondHalf == 10)
        #expect(backlog.atEnd > backlog.atMidpoint + 1)
        expectAccounted(r)
    }

    @Test func operationThatKeepsUpLeavesTheBacklogFlat() async throws {
        // 100 ops/s for 0.4 s with a no-op: each completes long before the next is due, so both samples are about 1
        // (the operation just launched). A loaded host can delay a no-op's task by a launch interval or so, which can
        // leave one more outstanding at either sample; allow 2 so the test checks flatness, not scheduling luck.
        let config = OpenLoopConfig(
            rate: 100, duration: .milliseconds(400), inFlightCap: 256, deadline: .seconds(5), drain: .seconds(1)
        )
        let r = await runOpenLoop(config) { _ in }
        let backlog = try #require(r.backlog)
        #expect(backlog.scheduledSecondHalf == 20)
        #expect(backlog.atEnd - backlog.atMidpoint <= 2)
        expectAccounted(r)
    }

    @Test func dropsAreNotBacklog() async throws {
        // Cap 2, operations that outlast the window: from index 2 on every index is a drop and the backlog stays at
        // the cap. Index 5 (100 ms of 200 ms) is the midpoint; with 0.1 s spans the midpoint span starts at index 0
        // (backlog 1), the end span at index 5 (backlog 2 from there on).
        let config = OpenLoopConfig(
            rate: 50, duration: .milliseconds(200), inFlightCap: 2, deadline: .seconds(2), drain: .milliseconds(100)
        )
        let r = await runOpenLoop(config) { _ in
            try await Task.sleep(for: .seconds(1))
        }
        #expect(r.dropped == 8)
        #expect(r.backlog == BacklogSamples(atMidpoint: 1, atEnd: 2, scheduledSecondHalf: 5))
        expectAccounted(r)
    }

    @Test func stallAtTheEndOfTheWindowIsNotGrowth() async throws {
        // 20 ops/s for 2 s: no-ops, except that indices 30-39 (1.5-1.95 s) each stall 600 ms. When scheduling ends
        // about 10 are outstanding, which a single sample at the end would read as growth (9 > max(1, 0.2, 5)); the
        // end span (1-2 s) also holds the no-ops before the stall, so its minimum is about 1.
        let config = OpenLoopConfig(
            rate: 20, duration: .seconds(2), inFlightCap: 256, deadline: .seconds(5), drain: .seconds(2)
        )
        let r = await runOpenLoop(config) { index in
            if index >= 30 { try await Task.sleep(for: .milliseconds(600)) }
        }
        #expect(r.succeeded == 40)
        let backlog = try #require(r.backlog)
        #expect(backlog.scheduledSecondHalf == 20)
        #expect(backlog.atEnd <= 2)
        #expect(!backlog.grew(targetRate: 20))
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

/// `BacklogWindows` over synthetic observations: which observations each minimum covers, and that a stall at the end
/// is a peak, not growth, while a rising floor is growth.
@Suite("Backlog windows")
struct BacklogWindowsTests {
    /// Observes `backlog(i)` for every index of a `seconds` window at `rate`, as `runOpenLoop` schedules them.
    private func samples(rate: Double, seconds: Double, _ backlog: (Int) -> Int) -> BacklogSamples? {
        let windowNanos = Int64(seconds * 1e9)
        let nanosPerOp = 1e9 / rate
        var windows = BacklogWindows(windowNanos: windowNanos, nanosPerOp: nanosPerOp)
        var index = 0
        while BacklogWindows.offset(index, nanosPerOp) < Double(windowNanos) {
            windows.observe(index: index, offsetNanos: BacklogWindows.offset(index, nanosPerOp), backlog: backlog(index))
            index += 1
        }
        return windows.samples(scheduled: index)
    }

    @Test func spansAreTheSecondEndingAtTheMidpointIndexAndTheLastSecond() throws {
        // 10/s for 10 s: the midpoint index is 50 (5 s); its span holds indices 40-50, the end span indices 90-99.
        // Each index observes its own number, so a minimum is its span's first index.
        let s = try #require(samples(rate: 10, seconds: 10) { $0 })
        #expect(s == BacklogSamples(atMidpoint: 40, atEnd: 90, scheduledSecondHalf: 50))
    }

    /// The CI case: a short server stall right at the end of scheduling left 181 outstanding at 250/s with no loss.
    @Test func stallInTheLastSecondIsNotGrowth() throws {
        // 250/s for 10 s, backlog 1, then a stall over the last 0.7 s: the backlog climbs to 175 by the end, which a
        // single sample there would read as growth (174 > max(1, 12.5, 62.5)).
        let atPeak = try #require(samples(rate: 250, seconds: 10) { $0 >= 2325 ? $0 - 2324 : 1 })
        #expect(atPeak.atMidpoint == 1 && atPeak.atEnd == 1)
        #expect(!atPeak.grew(targetRate: 250))
        // A stall from 8.8 s to 9.8 s that then clears (the backlog dips back to 1).
        let dipped = try #require(samples(rate: 250, seconds: 10) { (2200..<2450).contains($0) ? $0 - 2199 : 1 })
        #expect(dipped.atEnd == 1)
        #expect(!dipped.grew(targetRate: 250))
    }

    @Test func risingFloorIsGrowth() throws {
        // 100/s for 10 s, completing 10/s too slowly: the backlog rises by one every 10 indices. The minima are the
        // backlog a second before the midpoint and a second before the end: 41 and 91, a growth of 50 > max(1, 5, 25).
        let s = try #require(samples(rate: 100, seconds: 10) { $0 / 10 + 1 })
        #expect(s == BacklogSamples(atMidpoint: 41, atEnd: 91, scheduledSecondHalf: 500))
        #expect(s.grew(targetRate: 100))
    }

    @Test func windowsShorterThanTwoSecondsUseHalfTheWindow() throws {
        // 10/s for 1 s: spans of 0.5 s. The midpoint index 5 (0.5 s) closes the first half (indices 0-5), the end span
        // is the second half (indices 5-9); they share index 5.
        let s = try #require(samples(rate: 10, seconds: 1) { $0 })
        #expect(s == BacklogSamples(atMidpoint: 0, atEnd: 5, scheduledSecondHalf: 5))
    }

    @Test func rateBelowOnePerSpanKeepsTheLastIndex() throws {
        // 0.4/s for 10 s: offsets 0, 2.5, 5, 7.5 s. No index lies in the end span (9-10 s), so the end sample is the
        // last index's observation; the midpoint span (4-5 s) holds only the midpoint index 2.
        let s = try #require(samples(rate: 0.4, seconds: 10) { $0 * 10 })
        #expect(s == BacklogSamples(atMidpoint: 20, atEnd: 30, scheduledSecondHalf: 2))
    }

    @Test func noSamplesBeforeTheMidpointIndex() {
        var windows = BacklogWindows(windowNanos: 1_000_000_000, nanosPerOp: 1e8)
        for index in 0..<5 { windows.observe(index: index, offsetNanos: Double(index) * 1e8, backlog: 1) }
        #expect(windows.samples(scheduled: 5) == nil)
    }
}
