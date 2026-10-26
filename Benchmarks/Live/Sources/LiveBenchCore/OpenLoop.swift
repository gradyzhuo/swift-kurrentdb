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
/// - Latency is completion time minus the **scheduled** instant, so scheduler lag counts against the client. The only
///   exception is a launch slightly *before* the due instant (see `DueInstantWaker`), which is measured from the
///   launch so it is never under-charged.
/// - Completing at or past `scheduled + deadline` is a `.timeout`, never a success, even if the deadline timer has
///   not fired yet.
/// - If `inFlightCap` operations are outstanding at the due instant, the index is recorded as `.drop` and not run.
/// - A thrown error is `.failure`. An operation still outstanding at `scheduled + deadline` is `.timeout` and its
///   task is cancelled; the timeout is recorded at the deadline even if the operation ignores cancellation, and its
///   later completion is ignored. A timed-out operation stops counting toward `inFlightCap` once it is recorded.
/// - After the window, the call waits until everything is accounted for or `drain` elapses, whichever is first;
///   anything still outstanding then is `.timeout` and cancelled. The call does not wait for operations that ignore
///   cancellation: they are unstructured tasks whose results are discarded.
/// - If the calling task is cancelled, scheduling stops; indices already scheduled are still accounted for.
///
/// Harness floor: every latency includes the scheduler's own wake-up and task-start cost. Measured on an Apple Silicon
/// Mac in a release build with a no-op operation at 250-8000/s: p50 2-4 µs, p99 under 40 µs (see
/// `OpenLoopTests.noOpCalibrationFloor`). Any other driver compared against this one (the .NET driver, Task 10) must
/// use the same timing rules (latency from the scheduled instant, an untoleranced timer or equivalent overshoot
/// compensation) and meet a comparable no-op floor. Otherwise a ratio partly measures harness timers, not clients.
public func runOpenLoop(
    _ config: OpenLoopConfig,
    clock: some Clock<Duration> = ContinuousClock(),
    operation: @escaping @Sendable (_ index: Int) async throws -> Void
) async -> OutcomeRecorder {
    precondition(config.rate.isFinite && config.rate > 0, "rate must be a positive finite number")
    precondition(config.inFlightCap >= 0, "inFlightCap must not be negative")

    let ledger = OpenLoopLedger()
    let start = clock.now
    let windowNanos = config.duration.totalNanoseconds
    // Integer nanosecond offsets keep the schedule exact (no accumulated floating-point drift).
    let nanosPerOp = 1e9 / config.rate

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
        // The waker may return a little before the due instant (see `DueInstantWaker`). Latency runs from the later of
        // the due instant and the actual launch, so an early launch is never under-charged and a late one is charged
        // from the schedule (no coordinated omission).
        let launched = clock.now
        let latencyOrigin = max(scheduled, launched)
        ledger.launch(i, cap: config.inFlightCap) {
            Task {
                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        let outcome: Outcome
                        do {
                            try await operation(i)
                            let completed = clock.now
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
    return ledger.expireOutstanding()
}

/// Wakes the scheduling loop close to each due instant without spinning.
///
/// Latency is measured from the scheduled instant, so a late wake-up is charged to the client under test. A timer
/// with the default leeway wakes ~0.5-1 ms late. Even with `.zero` tolerance, an idle process overshoots by a roughly
/// constant amount (~350 µs on macOS at 1000/s, ~50 µs at 8000/s). The waker keeps an exponentially weighted estimate
/// of that overshoot and sleeps until `due - estimate`, so it usually wakes within tens of µs of `due`, sometimes
/// slightly before it. It does not spin to the exact instant: a spin cost 60-100% of a core at 4000-8000/s, which
/// would distort the client CPU figures. The caller measures latency from `max(due, actual launch)` instead. The
/// estimate is capped at `maxEstimate`, which bounds how early a launch can be.
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
    /// The task is created under the lock so its `finish` cannot run before it is tracked.
    func launch(_ index: Int, cap: Int, makeTask: () -> Task<Void, Never>) {
        state.withLock { s in
            if s.outstanding.count >= cap {
                s.recorder.record(.drop)
            } else {
                s.outstanding[index] = makeTask()
            }
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
    fileprivate var totalNanoseconds: Int64 {
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
