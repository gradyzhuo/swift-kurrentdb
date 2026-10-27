import Synchronization

/// Parameters of one open-loop measurement window.
public struct OpenLoopConfig: Sendable {
    /// Operations scheduled per second.
    public var rate: Double
    /// Length of the scheduling window. Operation *i* is scheduled at `start + i / rate` while that is before `start + duration`.
    public var duration: Duration
    /// Maximum number of unaccounted operations; an operation due while this many are outstanding is a `.drop`.
    public var inFlightCap: Int
    /// Per-operation deadline, measured from the operation's scheduled instant.
    public var deadline: Duration
    /// Bounded wait after the window ends; anything still unaccounted at `start + duration + drain` is a `.timeout`.
    public var drain: Duration

    public init(rate: Double, duration: Duration, inFlightCap: Int, deadline: Duration, drain: Duration) {
        self.rate = rate
        self.duration = duration
        self.inFlightCap = inFlightCap
        self.deadline = deadline
        self.drain = drain
    }
}

/// Runs `operation` open-loop at a fixed rate and accounts for every scheduled index exactly once.
///
/// - Operation *i* is due at `start + i / rate`. The scheduling loop only sleeps until each due instant and never waits
///   for completions, so a slow operation cannot delay later ones (no coordinated omission).
/// - Latency is completion time minus the **earlier** of the scheduled instant and the actual launch. A late launch is
///   charged from the schedule, so scheduler lag counts against the client (no coordinated omission). A launch
///   slightly before the due instant (see `DueInstantWaker`) is charged from the launch, so its head start is charged
///   too.
/// - Completing at or past `scheduled + deadline` is a `.timeout`, never a success, even if the deadline timer has
///   not fired yet.
/// - If `inFlightCap` operations are outstanding at the launch, the index is recorded as `.drop` and not run. The
///   launch, and so this check, may run up to the waker's overshoot estimate (at most 1 ms) before the due instant.
/// - A thrown error is `.failure`. An operation still outstanding at `scheduled + deadline` is `.timeout` and its
///   task is cancelled; the timeout is recorded at the deadline even if the operation ignores cancellation, and its
///   later completion is ignored. A timed-out operation stops counting toward `inFlightCap` once it is recorded.
/// - After the window, the call waits until everything is accounted for or `drain` elapses, whichever is first;
///   anything still outstanding then is `.timeout` and cancelled. The call does not wait for operations that ignore
///   cancellation: they are unstructured tasks whose results are discarded.
/// - If the calling task is cancelled, scheduling stops; indices already scheduled are still accounted for.
/// - The backlog (operations launched with no recorded outcome yet) is observed right after each index is launched or
///   dropped. The result's `backlog` holds its minimum over the trailing second of schedule that ends at the midpoint
///   index (the first index scheduled at or after `duration / 2`), its minimum over the last second of the window, and
///   the number of indices scheduled from the midpoint index on (`BacklogWindows`). It stays nil if scheduling stopped
///   before the midpoint. A backlog whose floor rises means completions fall behind the rate even if everything
///   finishes within the deadline and the drain (`backlogGrew`); a short stall only makes a peak, which the minimum
///   ignores.
///
/// Harness floor: every latency includes the scheduler's own wake-up error (early or late) and task-start cost.
/// Measured on an Apple Silicon Mac (macOS) in a release build with a no-op operation, p50 / p99:
/// 1000/s 4-7 / 150-190 µs, 4000/s 4-6 / 57-77 µs, 8000/s 6-7 / 126-380 µs. At 250/s the idle timer's jitter dominates:
/// about 350 / 1100 µs (a dedicated thread with a blocking sleep is worse, about 1.3 ms). See
/// `OpenLoopTests.noOpCalibrationFloor`. Any other driver compared against this one (the .NET driver, Task 10) must
/// use the same timing rules (latency from the scheduled instant, an untoleranced timer or equivalent overshoot
/// compensation) and meet a comparable no-op floor. Otherwise a ratio partly measures harness timers, not clients.
public func runOpenLoop(
    _ config: OpenLoopConfig,
    clock: some Clock<Duration> = ContinuousClock(),
    operation: @escaping @Sendable (_ index: Int) async throws -> Void
) async -> OutcomeRecorder {
    await runOpenLoop(config, clock: clock) { index in
        try await operation(index)
        return nil
    }
}

/// `runOpenLoop` for operations that know when they really completed: the operation returns its completion instant,
/// or nil for "now" (when it returns). Subscription kinds return the instant the receiving callback stamped, so the
/// hand-off from the callback to the operation's task is not part of the latency. Every other rule is unchanged:
/// latency runs from `min(scheduled, launch)` to the returned instant, and an instant at or past
/// `scheduled + deadline` is a `.timeout`. The deadline timer still fires at the deadline if the operation has not
/// returned by then.
public func runOpenLoop<C: Clock<Duration>>(
    _ config: OpenLoopConfig,
    clock: C,
    operation: @escaping @Sendable (_ index: Int) async throws -> C.Instant?
) async -> OutcomeRecorder {
    precondition(config.rate.isFinite && config.rate > 0, "rate must be a positive finite number")
    precondition(config.inFlightCap >= 0, "inFlightCap must not be negative")

    let ledger = OpenLoopLedger()
    let start = clock.now
    let windowNanos = config.duration.totalNanoseconds
    // Integer nanosecond offsets keep the schedule exact (no accumulated floating-point drift).
    let nanosPerOp = 1e9 / config.rate
    var backlogWindows = BacklogWindows(windowNanos: windowNanos, nanosPerOp: nanosPerOp)

    var waker = DueInstantWaker(clock: clock)
    var index = 0
    while true {
        let offsetNanos = (Double(index) * nanosPerOp).rounded()
        guard offsetNanos < Double(windowNanos) else { break }
        let scheduled = start.advanced(by: .nanoseconds(Int64(offsetNanos)))
        do {
            try await waker.wait(until: scheduled)
        } catch {
            break // the caller was cancelled: stop scheduling
        }
        let i = index
        // The waker may return a little before or after the due instant (see `DueInstantWaker`). Latency runs from the
        // earlier of the two: a late launch is charged from the schedule (no coordinated omission), an early one from
        // the launch (its head start is not free).
        let launched = clock.now
        let latencyOrigin = min(scheduled, launched)
        let backlog = ledger.launch(i, cap: config.inFlightCap) {
            Task {
                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        let outcome: Outcome
                        do {
                            let completed = try await operation(i) ?? clock.now
                            // The deadline child may not have run yet; finishing at or past the deadline is still a timeout.
                            outcome = scheduled.duration(to: completed) >= config.deadline
                                ? .timeout
                                : .success(latencyMicros: latencyOrigin.duration(to: completed).wholeMicroseconds)
                        } catch {
                            outcome = .failure
                        }
                        ledger.finish(i, outcome)
                    }
                    group.addTask {
                        // A cancelled sleep means the operation finished first: nothing to record.
                        guard (try? await clock.sleep(until: scheduled.advanced(by: config.deadline), tolerance: .zero)) != nil else { return }
                        ledger.finish(i, .timeout)
                    }
                    // Whichever child finishes first has recorded the outcome; cancel the other. If the operation ignores
                    // cancellation this group lingers, but nothing awaits it and its late result is ignored.
                    await group.next()
                    group.cancelAll()
                }
            }
        }
        backlogWindows.observe(index: i, offsetNanos: offsetNanos, backlog: backlog)
        index += 1
    }

    // Drain: wait for everything to be accounted for, bounded by the end of the window plus `drain`.
    let drainEnd = start.advanced(by: config.duration + config.drain)
    let allAccounted = ledger.closeScheduling()
    await withTaskGroup(of: Void.self) { group in
        group.addTask { for await _ in allAccounted {} } // ends when everything is accounted for, or on cancellation
        group.addTask { try? await clock.sleep(until: drainEnd, tolerance: nil) }
        await group.next()
        group.cancelAll()
    }
    var recorder = ledger.expireOutstanding()
    // `index` is one past the last index scheduled (launched or dropped).
    recorder.backlog = backlogWindows.samples(scheduled: index)
    return recorder
}

/// Folds the backlog observed right after each index is launched or dropped into `BacklogSamples` (driver contract
/// rule 11). A sample is the **minimum** over a trailing span of `span = min(1 s, duration / 2)` of schedule, by
/// the indices' integer-nanosecond offsets (the same rounded offsets that decide whether an index is in the window):
///
/// - midpoint: the indices with offsets in `[offset(m) - span, offset(m)]`, where `m`, the midpoint index, is the first
///   index whose offset is at or after `duration / 2`;
/// - end: the indices with offsets in `[duration - span, duration)`, and always the last index scheduled (so a rate
///   below one per span, or a loop stopped early, still has one observation).
///
/// A client that falls behind raises the backlog's floor, so the minimum rises with it; a stall shorter than the
/// span only adds a peak, and the observations before or after it keep the minimum low. For windows of 2 s or more
/// the span is 1 s; a shorter window uses half of it, so the two spans cover the first half (up to `m`) and the second
/// half and share at most index `m`. Either way the two minima are about half a window apart, like the
/// `scheduledSecondHalf` that scales the growth tolerance.
struct BacklogWindows: Sendable {
    let spanNanos: Int64
    let midpointIndex: Int
    /// Offsets at which the midpoint span and the end span start.
    private let midpointSpanStart: Double
    private let endSpanStart: Double
    private var midpointMin: Int?
    private var endMin: Int?
    private var last: Int?

    init(windowNanos: Int64, nanosPerOp: Double) {
        spanNanos = min(1_000_000_000, windowNanos / 2)
        // The first index whose rounded offset is at or after half the window, found from an estimate below it.
        let midpointNanos = Double(windowNanos) / 2
        var m = max(0, Int(midpointNanos / nanosPerOp) - 1)
        while m > 0, Self.offset(m - 1, nanosPerOp) >= midpointNanos { m -= 1 }
        while Self.offset(m, nanosPerOp) < midpointNanos { m += 1 }
        midpointIndex = m
        midpointSpanStart = Self.offset(m, nanosPerOp) - Double(spanNanos)
        endSpanStart = Double(windowNanos - spanNanos)
    }

    /// Integer-nanosecond offset of `index` from the window's start (`runOpenLoop`'s schedule).
    static func offset(_ index: Int, _ nanosPerOp: Double) -> Double {
        (Double(index) * nanosPerOp).rounded()
    }

    /// The backlog right after `index` (offset `offsetNanos`) was launched or dropped; indices arrive in order.
    mutating func observe(index: Int, offsetNanos: Double, backlog: Int) {
        if index <= midpointIndex, offsetNanos >= midpointSpanStart { midpointMin = min(midpointMin ?? backlog, backlog) }
        if offsetNanos >= endSpanStart { endMin = min(endMin ?? backlog, backlog) }
        last = backlog
    }

    /// The samples once `scheduled` indices (0 ..< scheduled) were observed; nil if scheduling never reached the
    /// midpoint index.
    func samples(scheduled: Int) -> BacklogSamples? {
        guard scheduled > midpointIndex, let midpointMin, let last else { return nil }
        return BacklogSamples(
            atMidpoint: midpointMin, atEnd: min(endMin ?? last, last), scheduledSecondHalf: scheduled - midpointIndex
        )
    }
}

/// Wakes the scheduling loop close to each due instant without spinning.
///
/// The caller charges latency from `min(due, actual launch)`, so any wake-up error, early or late, ends up in the
/// measured latency; this type exists to keep that error small. A timer
/// with the default leeway wakes ~0.5-1 ms late. Even with `.zero` tolerance, an idle process overshoots by a roughly
/// constant amount (~350 µs on macOS at 1000/s, ~50 µs at 8000/s). The waker keeps an exponentially weighted estimate
/// of that overshoot and sleeps until `due - estimate`, so it usually wakes within tens of µs of `due`, sometimes
/// slightly before it. It does not spin to the exact instant: a spin cost 60-100% of a core at 4000-8000/s, which
/// would distort the client CPU figures. The estimate is capped at `maxEstimate`, which bounds how early a launch can be.
private struct DueInstantWaker<C: Clock<Duration>> {
    private static var maxEstimate: Duration { .milliseconds(1) }
    let clock: C
    private var overshootEstimate = Duration.zero

    init(clock: C) {
        self.clock = clock
    }

    mutating func wait(until due: C.Instant) async throws {
        let wakeAt = due.advanced(by: .zero - overshootEstimate)
        guard clock.now < wakeAt else {
            try Task.checkCancellation()
            return
        }
        try await clock.sleep(until: wakeAt, tolerance: .zero)
        // Learn only from real sleeps; a loop already behind schedule says nothing about the timer.
        let overshoot = wakeAt.duration(to: clock.now)
        overshootEstimate += (overshoot - overshootEstimate) / 16
        overshootEstimate = min(max(overshootEstimate, .zero), Self.maxEstimate)
    }
}

/// Shared, lock-protected accounting: each index is recorded at most once, by whichever path gets there first.
private final class OpenLoopLedger: Sendable {
    private struct State {
        var recorder = OutcomeRecorder()
        var outstanding: [Int: Task<Void, Never>] = [:]
        var schedulingClosed = false
    }

    private let state = Mutex(State())
    private let allAccounted: AsyncStream<Void>
    private let allAccountedContinuation: AsyncStream<Void>.Continuation

    init() {
        (allAccounted, allAccountedContinuation) = AsyncStream<Void>.makeStream()
    }

    /// Records a drop if the cap is reached; otherwise starts the operation's task and tracks it as outstanding.
    /// The task is created under the lock so its `finish` cannot run before it is tracked. Returns the backlog
    /// (outstanding count) right after.
    func launch(_ index: Int, cap: Int, makeTask: () -> Task<Void, Never>) -> Int {
        state.withLock { s in
            if s.outstanding.count >= cap {
                s.recorder.record(.drop)
            } else {
                s.outstanding[index] = makeTask()
            }
            return s.outstanding.count
        }
    }

    /// Records the outcome if `index` is still outstanding; a later second outcome for the same index is ignored.
    func finish(_ index: Int, _ outcome: Outcome) {
        let nowEmpty = state.withLock { s -> Bool in
            guard s.outstanding.removeValue(forKey: index) != nil else { return false }
            s.recorder.record(outcome)
            return s.schedulingClosed && s.outstanding.isEmpty
        }
        if nowEmpty { allAccountedContinuation.finish() }
    }

    /// Marks the end of scheduling and returns a stream that finishes once nothing is outstanding.
    func closeScheduling() -> AsyncStream<Void> {
        let empty = state.withLock { s -> Bool in
            s.schedulingClosed = true
            return s.outstanding.isEmpty
        }
        if empty { allAccountedContinuation.finish() }
        return allAccounted
    }

    /// Records every outstanding operation as `.timeout`, cancels it without awaiting it, and returns the final tally.
    func expireOutstanding() -> OutcomeRecorder {
        let (recorder, leftovers) = state.withLock { s in
            let leftovers = Array(s.outstanding.values)
            for _ in leftovers { s.recorder.record(.timeout) }
            s.outstanding.removeAll()
            return (s.recorder, leftovers)
        }
        allAccountedContinuation.finish()
        for task in leftovers { task.cancel() }
        return recorder
    }
}

extension Duration {
    /// The duration in whole nanoseconds.
    public var totalNanoseconds: Int64 {
        let (seconds, attoseconds) = components
        return seconds * 1_000_000_000 + attoseconds / 1_000_000_000
    }

    /// Whole microseconds, clamped at zero.
    fileprivate var wholeMicroseconds: UInt64 {
        let (seconds, attoseconds) = components
        let micros = seconds * 1_000_000 + attoseconds / 1_000_000_000_000
        return micros > 0 ? UInt64(micros) : 0
    }
}
