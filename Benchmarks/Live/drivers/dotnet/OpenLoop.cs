// The open-loop load model of docs/driver-contract.md ("Load model"), mirroring Sources/LiveBenchCore/OpenLoop.swift
// rule for rule. Instants are monotonic nanoseconds (`MonoClock.Now`).

using System.Diagnostics;
using System.Runtime.InteropServices;
using HdrHistogram;

namespace LiveDriver;

/// Monotonic clock in nanoseconds (Stopwatch: CLOCK_MONOTONIC on Linux, mach_continuous_time-based on macOS).
static class MonoClock
{
    static readonly bool NativeNanos = Stopwatch.Frequency == 1_000_000_000;
    static readonly double NanosPerTick = 1e9 / Stopwatch.Frequency;

    public static long Now() => NativeNanos ? Stopwatch.GetTimestamp() : (long)(Stopwatch.GetTimestamp() * NanosPerTick);
}

/// Parameters of one open-loop window (`OpenLoopConfig`).
sealed record OpenLoopConfig(double Rate, long DurationNanos, int InFlightCap, long DeadlineNanos, long DrainNanos);

enum OutcomeKind { Success, Failure, Drop, Timeout }

readonly record struct Outcome(OutcomeKind Kind, ulong LatencyMicros = 0)
{
    public static readonly Outcome Failure = new(OutcomeKind.Failure);
    public static readonly Outcome Drop = new(OutcomeKind.Drop);
    public static readonly Outcome Timeout = new(OutcomeKind.Timeout);
    public static Outcome Success(ulong micros) => new(OutcomeKind.Success, micros);
}

/// The open loop's backlog (operations launched with no recorded outcome yet; drops are not backlog), sampled at the
/// window's midpoint and at the end of scheduling (`BacklogSamples`, Outcomes.swift).
readonly record struct BacklogSamples(int AtMidpoint, int AtEnd, int ScheduledSecondHalf);

/// Counts every scheduled attempt and keeps a latency histogram of the successes only (Outcomes.swift):
/// 1 us to 60 s, 3 significant digits; a success is clamped to that range.
sealed class OutcomeRecorder
{
    public long Succeeded { get; private set; }
    public long Failed { get; private set; }
    public long Dropped { get; private set; }
    public long TimedOut { get; private set; }
    public LongHistogram Histogram { get; } = new(1, 60_000_000, 3);
    public long Scheduled => Succeeded + Failed + Dropped + TimedOut;
    /// Set by `OpenLoop.Run` once its schedule reached the window's midpoint; null otherwise.
    public BacklogSamples? Backlog { get; set; }

    public void Record(Outcome outcome)
    {
        switch (outcome.Kind)
        {
            case OutcomeKind.Success:
                Succeeded++;
                Histogram.RecordValue((long)Math.Clamp(outcome.LatencyMicros, 1UL, 60_000_000UL));
                break;
            case OutcomeKind.Failure: Failed++; break;
            case OutcomeKind.Drop: Dropped++; break;
            case OutcomeKind.Timeout: TimedOut++; break;
        }
    }
}

/// The operation of index i. It returns its completion instant (`MonoClock.Now` nanoseconds), or null for "when the
/// returned task completes". Subscription kinds return the instant the receiving callback stamped. The token is
/// cancelled when the operation's deadline passes (or the drain ends) and its outcome is already a timeout.
delegate Task<long?> OpenLoopOperation(int index, CancellationToken cancellationToken);

static class OpenLoop
{
    /// Runs `operation` open-loop at a fixed rate and accounts for every scheduled index exactly once
    /// (`runOpenLoop`):
    /// - Operation i is due at `start + i / rate` while that is before `start + duration`. A dedicated scheduling
    ///   thread sleeps until each due instant (`DueInstantWaker`) and never waits for completions (no coordinated
    ///   omission); each operation runs on the thread pool, like a Swift `Task {}`.
    /// - Latency is completion minus `min(scheduled, actual launch)`.
    /// - At launch, if `inFlightCap` operations have no recorded outcome yet, the index is a drop and is not run.
    /// - Completing at or past `scheduled + deadline` is a timeout, never a success. An operation still outstanding
    ///   at its deadline is recorded as a timeout then and cancelled; its later completion is ignored, and it stops
    ///   counting towards the cap.
    /// - A thrown exception is a failure.
    /// - After the window: wait until nothing is outstanding or `start + duration + drain`; everything still
    ///   outstanding then is a timeout and is cancelled (not awaited).
    /// - The backlog (outstanding operations) is sampled right after the first index scheduled at or after
    ///   `duration / 2` is launched or dropped, and again when scheduling ends, before the drain; `Backlog` holds both
    ///   and the number of indices scheduled from the midpoint index on (null if scheduling never reached it).
    public static async Task<OutcomeRecorder> Run(OpenLoopConfig config, OpenLoopOperation operation)
    {
        if (!double.IsFinite(config.Rate) || config.Rate <= 0) throw new ArgumentException("rate must be a positive finite number");
        if (config.InFlightCap < 0) throw new ArgumentException("inFlightCap must not be negative");

        var ledger = new Ledger(config, operation);
        long start = MonoClock.Now();
        double nanosPerOp = 1e9 / config.Rate;
        double midpointNanos = config.DurationNanos / 2.0;
        // Index and backlog of the first launch at or after the window's midpoint; `scheduledCount` is one past the
        // last index scheduled. Written by the scheduling thread, read after `schedulingDone`.
        (int Index, int Backlog)? midpoint = null;
        int scheduledCount = 0;
        var schedulingDone = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var scheduler = new Thread(() =>
        {
            try
            {
                var waker = new DueInstantWaker();
                for (int index = 0; ; index++)
                {
                    // Integer nanosecond offsets keep the schedule exact (no accumulated floating-point drift).
                    double offset = Math.Round(index * nanosPerOp, MidpointRounding.AwayFromZero);
                    if (!(offset < config.DurationNanos)) break;
                    scheduledCount = index + 1;
                    long scheduled = start + (long)offset;
                    waker.Wait(scheduled);
                    // The waker may return a little before or after the due instant. Latency runs from the earlier of
                    // the two: a late launch is charged from the schedule, an early one from the launch.
                    long launched = MonoClock.Now();
                    int backlog = ledger.Launch(index, scheduled, Math.Min(scheduled, launched));
                    if (midpoint is null && offset >= midpointNanos) midpoint = (index, backlog);
                }
                schedulingDone.SetResult();
            }
            catch (Exception e)
            {
                schedulingDone.SetException(e);
            }
        })
        {
            IsBackground = true,
            Name = "open-loop scheduler",
        };
        scheduler.Start();
        await schedulingDone.Task.ConfigureAwait(false);

        // Drain: wait for everything to be accounted for, bounded by the end of the window plus `drain`.
        var (allAccounted, backlogAtEnd) = ledger.CloseScheduling();
        long drainEnd = start + config.DurationNanos + config.DrainNanos;
        // Task.Delay works in whole milliseconds (TimeSpanUntil rounds up), so loop until the drain end has really passed:
        // nothing outstanding is expired before it.
        while (!allAccounted.IsCompleted && MonoClock.Now() < drainEnd)
            await Task.WhenAny(allAccounted, Task.Delay(TimeSpanUntil(drainEnd))).ConfigureAwait(false);
        var recorder = ledger.ExpireOutstanding();
        if (midpoint is { } m) recorder.Backlog = new BacklogSamples(m.Backlog, backlogAtEnd, scheduledCount - m.Index);
        return recorder;
    }

    /// Shared, lock-protected accounting (`OpenLoopLedger`): each index is recorded at most once, by whichever path
    /// gets there first (the operation, its deadline timer, or the end of the drain).
    sealed class Ledger(OpenLoopConfig config, OpenLoopOperation operation)
    {
        readonly object _gate = new();
        readonly OutcomeRecorder _recorder = new();
        readonly Dictionary<int, CancellationTokenSource> _outstanding = new();
        readonly TaskCompletionSource _allAccounted = new(TaskCreationOptions.RunContinuationsAsynchronously);
        bool _schedulingClosed;

        /// Records a drop if the cap is reached; otherwise tracks the operation as outstanding, then starts it on the
        /// thread pool together with its deadline timer. It is tracked before it starts, so its outcome always finds it.
        /// Returns the backlog (outstanding count) right after.
        public int Launch(int index, long scheduled, long latencyOrigin)
        {
            var cts = new CancellationTokenSource();
            int backlog;
            lock (_gate)
            {
                if (_outstanding.Count >= config.InFlightCap)
                {
                    _recorder.Record(Outcome.Drop);
                    cts.Dispose();
                    return _outstanding.Count;
                }
                _outstanding[index] = cts;
                backlog = _outstanding.Count;
            }
            // Deadline: an operation still outstanding at `scheduled + deadline` is a timeout, recorded then. (The
            // timer only frees the cap slot and cancels; a late completion is judged by its own instant below.)
            cts.Token.Register(static state =>
            {
                var (ledger, i) = ((Ledger, int))state!;
                ledger.Finish(i, Outcome.Timeout);
            }, (this, index));
            // CancelAfter's timer works in whole milliseconds and may fire up to about a millisecond before the
            // requested span: rounding up plus one millisecond keeps the timeout at or after `scheduled + deadline`.
            cts.CancelAfter(TimeSpanUntil(scheduled + config.DeadlineNanos));
            ThreadPool.UnsafeQueueUserWorkItem(static s => _ = s.ledger.Execute(s.index, s.scheduled, s.latencyOrigin, s.cts),
                (ledger: this, index, scheduled, latencyOrigin, cts), preferLocal: false);
            return backlog;
        }

        async Task Execute(int index, long scheduled, long latencyOrigin, CancellationTokenSource cts)
        {
            Outcome outcome;
            try
            {
                long completed = await operation(index, cts.Token).ConfigureAwait(false) ?? MonoClock.Now();
                // The deadline timer may not have fired yet; finishing at or past the deadline is still a timeout.
                outcome = completed - scheduled >= config.DeadlineNanos
                    ? Outcome.Timeout
                    : Outcome.Success(WholeMicros(completed - latencyOrigin));
            }
            catch
            {
                // Cancellation callbacks run in reverse registration order, so the operation's own cancellation (and
                // its exception) can come before the ledger's timeout callback has recorded the timeout. The token is
                // cancelled only at the deadline or at the drain end, so an operation that ends because of it is a
                // timeout, never a failure, whichever thread gets to the ledger first.
                outcome = cts.IsCancellationRequested ? Outcome.Timeout : Outcome.Failure;
            }
            Finish(index, outcome);
            cts.Dispose(); // stops the deadline timer; a cancellation already in flight is harmless (Finish ignores it)
        }

        /// Records the outcome if `index` is still outstanding; a later second outcome for the same index is ignored.
        public void Finish(int index, Outcome outcome)
        {
            bool nowEmpty;
            lock (_gate)
            {
                if (!_outstanding.Remove(index)) return;
                _recorder.Record(outcome);
                nowEmpty = _schedulingClosed && _outstanding.Count == 0;
            }
            if (nowEmpty) _allAccounted.TrySetResult();
        }

        /// Marks the end of scheduling; the task completes once nothing is outstanding. Also returns the backlog
        /// (outstanding count) at that moment.
        public (Task AllAccounted, int Backlog) CloseScheduling()
        {
            lock (_gate)
            {
                _schedulingClosed = true;
                if (_outstanding.Count == 0) _allAccounted.TrySetResult();
                return (_allAccounted.Task, _outstanding.Count);
            }
        }

        /// Records every outstanding operation as a timeout, cancels it without awaiting it, and returns the tally.
        public OutcomeRecorder ExpireOutstanding()
        {
            List<CancellationTokenSource> leftovers;
            lock (_gate)
            {
                leftovers = [.. _outstanding.Values];
                foreach (var _ in leftovers) _recorder.Record(Outcome.Timeout);
                _outstanding.Clear();
            }
            _allAccounted.TrySetResult();
            foreach (var cts in leftovers) CancelQuietly(cts);
            lock (_gate) return _recorder;
        }

        static void CancelQuietly(CancellationTokenSource cts)
        {
            // After Execute disposed it there is nothing left to cancel.
            try { cts.Cancel(); } catch (ObjectDisposedException) { } catch (AggregateException) { }
        }
    }

    /// The span from now until `instant` for a millisecond timer: whole milliseconds rounded up, plus one, so the timer
    /// never fires before `instant` (zero if it has passed).
    static TimeSpan TimeSpanUntil(long instant)
    {
        long nanos = instant - MonoClock.Now();
        return nanos <= 0 ? TimeSpan.Zero : TimeSpan.FromMilliseconds((nanos + 999_999) / 1_000_000 + 1);
    }

    /// Whole microseconds, clamped at zero.
    static ulong WholeMicros(long nanos) => nanos > 0 ? (ulong)(nanos / 1000) : 0;

    /// Wakes the scheduling thread close to each due instant without spinning (`DueInstantWaker`).
    ///
    /// The thread blocks in `nanosleep` (no timer slack is requested, unlike `Task.Delay` / `Thread.Sleep`, which work
    /// in whole milliseconds), then keeps an exponentially weighted estimate of the sleep's overshoot and sleeps until
    /// `due - estimate`, so it usually wakes within tens of µs of `due`, sometimes slightly before it. Like the Swift
    /// waker it does not spin to the exact instant (a spin would distort the client CPU figures). The estimate is
    /// capped at 1 ms, which bounds how early a launch can be.
    sealed class DueInstantWaker
    {
        const long MaxEstimate = 1_000_000;
        long _overshootEstimate;

        public void Wait(long due)
        {
            long wakeAt = due - _overshootEstimate;
            long now = MonoClock.Now();
            if (now >= wakeAt) return;
            NativeSleep.Sleep(wakeAt - now);
            // Learn only from real sleeps; a loop already behind schedule says nothing about the timer.
            long overshoot = MonoClock.Now() - wakeAt;
            _overshootEstimate += (overshoot - _overshootEstimate) / 16;
            _overshootEstimate = Math.Clamp(_overshootEstimate, 0, MaxEstimate);
        }
    }
}

/// A blocking relative sleep with nanosecond resolution: `nanosleep(2)` on Linux and macOS.
static class NativeSleep
{
    [StructLayout(LayoutKind.Sequential)]
    struct Timespec
    {
        public long Seconds;
        public long Nanoseconds;
    }

    [DllImport("libc", SetLastError = true)]
    static extern int nanosleep(ref Timespec request, out Timespec remaining);

    const int EINTR = 4;

    public static void Sleep(long nanos)
    {
        if (nanos <= 0) return;
        if (OperatingSystem.IsWindows())
        {
            Thread.Sleep(TimeSpan.FromTicks(nanos / 100));
            return;
        }
        var request = new Timespec { Seconds = nanos / 1_000_000_000, Nanoseconds = nanos % 1_000_000_000 };
        while (nanosleep(ref request, out var remaining) != 0 && Marshal.GetLastPInvokeError() == EINTR)
            request = remaining;
    }
}
