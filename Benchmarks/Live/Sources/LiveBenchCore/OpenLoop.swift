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
/// - Latency is completion time minus the **scheduled** instant, so scheduler lag counts against the client.
/// - If `inFlightCap` operations are outstanding at the due instant, the index is recorded as `.drop` and not run.
/// - A thrown error is `.failure`. An operation still outstanding at `scheduled + deadline` is `.timeout` and its
///   task is cancelled; the timeout is recorded at the deadline even if the operation ignores cancellation, and its
///   later completion is ignored. A timed-out operation stops counting toward `inFlightCap` once it is recorded.
/// - After the window, the call waits until everything is accounted for or `drain` elapses, whichever is first;
///   anything still outstanding then is `.timeout` and cancelled. The call does not wait for operations that ignore
///   cancellation: they are unstructured tasks whose results are discarded.
/// - If the calling task is cancelled, scheduling stops; indices already scheduled are still accounted for.
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

    var index = 0
    while true {
        let offsetNanos = (Double(index) * nanosPerOp).rounded()
        guard offsetNanos < Double(windowNanos) else { break }
        let scheduled = start.advanced(by: .nanoseconds(Int64(offsetNanos)))
        do {
            try await clock.sleep(until: scheduled, tolerance: nil)
        } catch {
            break // the caller was cancelled: stop scheduling
        }
        let i = index
        ledger.launch(i, cap: config.inFlightCap) {
            Task {
                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        let outcome: Outcome
                        do {
                            try await operation(i)
                            outcome = .success(latencyMicros: scheduled.duration(to: clock.now).wholeMicroseconds)
                        } catch {
                            outcome = .failure
                        }
                        ledger.finish(i, outcome)
                    }
                    group.addTask {
                        // A cancelled sleep means the operation finished first: nothing to record.
                        guard (try? await clock.sleep(until: scheduled.advanced(by: config.deadline), tolerance: nil)) != nil else { return }
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
