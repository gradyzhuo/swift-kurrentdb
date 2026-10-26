// What each kind schedules (docs/driver-contract.md, "What each kind schedules"), mirroring the Swift driver's
// Append.swift, Rebuild.swift and Subscriptions.swift on the official KurrentDB.Client with default settings.

using System.Text.Json;
using KurrentDB.Client;

namespace LiveDriver;

/// What a kind's run produced; turned into `result.json` by `Result`.
sealed record Trial(
    OutcomeRecorder Recorder,
    (double User, double System) Cpu,
    double MeasuredSeconds,
    Validation Validation,
    int? AckEnqueued = null,
    int? UniqueDeliveries = null,
    int? Redeliveries = null,
    double? CatchUpSeconds = null)
{
    public TrialResult Result(EffectiveScenario scenario) => new(
        Client: "dotnet", CellId: scenario.CellId, TargetRate: scenario.Rate, Timing: "scheduled",
        Scheduled: Recorder.Scheduled, Succeeded: Recorder.Succeeded, Failed: Recorder.Failed,
        Dropped: Recorder.Dropped, TimedOut: Recorder.TimedOut,
        MeasuredSeconds: MeasuredSeconds, CpuUserSeconds: Cpu.User, CpuSystemSeconds: Cpu.System,
        MaxRssBytes: ProcessUsage.Current().MaxRss,
        AckEnqueued: AckEnqueued, UniqueDeliveries: UniqueDeliveries, Redeliveries: Redeliveries,
        CatchUpSeconds: CatchUpSeconds, Validation: Validation);
}

/// Names a phase works on: the measured ones, or the warmup ones (`streamPrefix + "w"`, `category + "w"`).
sealed record Names(string StreamPrefix, string Category)
{
    public static Names Measured(EffectiveScenario s) => new(s.StreamPrefix, s.Category);
    public static Names Warmup(EffectiveScenario s) => new(s.StreamPrefix + "w", s.Category + "w");

    /// `<streamPrefix>-<n>` for the seeded pick of operation `index` among `count` streams.
    public string Stream(ulong seed, int index, int count) => $"{StreamPrefix}-{SeededDraw.Pick(seed, index, count)}";

    public string CategoryStream => $"$ce-{Category}";
}

/// The clients of one run, all built from the connection string with default settings. KurrentDB.Client splits
/// streams and persistent subscriptions into two client classes; each owns its own gRPC channel.
sealed class Clients(KurrentDBClientSettings settings) : IAsyncDisposable
{
    public KurrentDBClient Streams { get; } = new(settings);
    readonly Lazy<KurrentDBPersistentSubscriptionsClient> _persistent = new(() => new KurrentDBPersistentSubscriptionsClient(settings));
    public KurrentDBPersistentSubscriptionsClient PersistentSubscriptions => _persistent.Value;

    public async ValueTask DisposeAsync()
    {
        if (_persistent.IsValueCreated) await _persistent.Value.DisposeAsync();
        await Streams.DisposeAsync();
    }
}

static class Scenarios
{
    // MARK: Common

    /// Event `index` of the contract's payload layout: type `BenchEvent`, JSON data and metadata of the scenario's
    /// sizes, built inline on the operation path from the factory's precomputed pools.
    static EventData BenchEvent(PayloadFactory payloads, long index) =>
        new(Uuid.NewUuid(), "BenchEvent", payloads.Data(index), payloads.Metadata(index), "application/json");

    /// The `batchSize` events of operation `i`: indices `i * batchSize ..< (i + 1) * batchSize`.
    static EventData[] OperationEvents(PayloadFactory payloads, int batchSize, int i)
    {
        var events = new EventData[batchSize];
        for (int j = 0; j < batchSize; j++) events[j] = BenchEvent(payloads, (long)i * batchSize + j);
        return events;
    }

    static PayloadFactory MakePayloads(EffectiveScenario s) => new(s.EventSize, s.MetadataSize, s.Seed);

    /// Runs one open-loop window and measures the process CPU it used (from its start to the end of its drain).
    static async Task<(OutcomeRecorder Recorder, (double User, double System) Cpu)> MeasuredWindow(OpenLoopConfig config, OpenLoopOperation operation)
    {
        var before = ProcessUsage.Current();
        var recorder = await OpenLoop.Run(config, operation);
        var after = ProcessUsage.Current();
        return (recorder, (after.User - before.User, after.System - before.System));
    }

    // MARK: Append

    /// `appendLatency` / `appendThroughput`: operation i appends `batchSize` events (indices `i * batchSize + j`) in
    /// one call to `<streamPrefix>-<pick(i)>` with expected state Any.
    public static async Task<Trial> RunAppend(EffectiveScenario s, Clients clients)
    {
        var payloads = MakePayloads(s);
        if (s.WarmupSeconds > 0)
        {
            Log.Info("warmup");
            await AppendWindow(s, clients.Streams, payloads, Names.Warmup(s), s.WarmupSeconds);
        }
        Log.Info("measure");
        Log.MarkMeasureStart();
        var (recorder, cpu) = await AppendWindow(s, clients.Streams, payloads, Names.Measured(s), s.MeasureSeconds);
        // Informational for append kinds: every succeeded operation is an acknowledged append of `batchSize` events.
        int events = (int)recorder.Succeeded * s.BatchSize;
        bool sizesOk = payloads.Data(0).Length == s.EventSize && payloads.Metadata(0).Length == s.MetadataSize;
        return new Trial(recorder, cpu, s.MeasureSeconds, new Validation(events, events, sizesOk));
    }

    static Task<(OutcomeRecorder, (double, double))> AppendWindow(EffectiveScenario s, KurrentDBClient client, PayloadFactory payloads, Names names, double seconds)
    {
        ulong seed = s.Seed;
        int streamCount = s.StreamCount, batchSize = s.BatchSize;
        return MeasuredWindow(s.OpenLoop(seconds), async (i, ct) =>
        {
            string stream = names.Stream(seed, i, streamCount);
            await client.AppendToStreamAsync(stream, StreamState.Any, OperationEvents(payloads, batchSize, i), cancellationToken: ct).ConfigureAwait(false);
            return null;
        });
    }

    // MARK: Rebuild

    /// `rebuild`: operation i reads one whole stream forward from the start (`rebuildStreams[pick(i)]`; warmup reads
    /// `<streamPrefix>w-<pick(i)>`), parsing every event's data into a JSON DOM (`JsonDocument.Parse`). A read that does
    /// not return exactly `streamLength` events is a failure.
    public static async Task<Trial> RunRebuild(EffectiveScenario s, Clients clients)
    {
        var streams = s.RebuildStreams!;
        if (s.WarmupSeconds > 0)
        {
            Log.Info("warmup");
            var warmup = Names.Warmup(s);
            await RebuildWindow(s, clients.Streams, s.WarmupSeconds, new RebuildTally(), i => warmup.Stream(s.Seed, i, streams.Count));
        }
        Log.Info("measure");
        var tally = new RebuildTally();
        Log.MarkMeasureStart();
        var (recorder, cpu) = await RebuildWindow(s, clients.Streams, s.MeasureSeconds, tally, i => streams[SeededDraw.Pick(s.Seed, i, streams.Count)]);
        int length = s.StreamLength ?? 0;
        var t = tally.Snapshot();
        // Seeded count (hard): reads that returned the wrong number of events show up as received != expected.
        return new Trial(recorder, cpu, s.MeasureSeconds, new Validation(
            ExpectedEvents: ((int)recorder.Succeeded + t.ShortReads) * length,
            ReceivedEvents: (int)recorder.Succeeded * length + t.ShortReadEvents,
            PayloadSizesOk: t.SizesOk));
    }

    sealed class RebuildMismatch(int events) : Exception($"read {events} events");

    /// Measure-window bookkeeping that the outcome counters cannot carry.
    sealed class RebuildTally
    {
        readonly object _gate = new();
        int _shortReads, _shortReadEvents;
        bool _sizesOk = true;

        public void Record(int events, int expected, bool sizesOk)
        {
            lock (_gate)
            {
                if (!sizesOk) _sizesOk = false;
                if (events != expected)
                {
                    _shortReads++;
                    _shortReadEvents += events;
                }
            }
        }

        public (int ShortReads, int ShortReadEvents, bool SizesOk) Snapshot()
        {
            lock (_gate) return (_shortReads, _shortReadEvents, _sizesOk);
        }
    }

    static Task<(OutcomeRecorder, (double, double))> RebuildWindow(EffectiveScenario s, KurrentDBClient client, double seconds, RebuildTally tally, Func<int, string> stream)
    {
        int length = s.StreamLength ?? 0, eventSize = s.EventSize, metadataSize = s.MetadataSize;
        return MeasuredWindow(s.OpenLoop(seconds), async (i, ct) =>
        {
            int events = 0;
            bool sizesOk = true;
            var read = client.ReadStreamAsync(Direction.Forwards, stream(i), StreamPosition.Start, cancellationToken: ct);
            await foreach (var resolved in read.ConfigureAwait(false))
            {
                var record = resolved.Event;
                using (JsonDocument.Parse(record.Data)) { }
                if (record.Data.Length != eventSize || record.Metadata.Length != metadataSize) sizesOk = false;
                events++;
            }
            // A missing stream is an error of the read itself (the Swift SDK throws), not a short read.
            if (events == 0 && await read.ReadState.ConfigureAwait(false) == ReadState.StreamNotFound)
                throw new InvalidOperationException($"stream {stream(i)} not found");
            tally.Record(events, length, sizesOk);
            if (events != length) throw new RebuildMismatch(events);
            return null;
        });
    }

    // MARK: Persistent subscription

    /// Seconds the measured consumers stay connected after the drain (driver contract, "Persistent subscription").
    const double PersistentAckSettleSeconds = 3.0;

    /// `persistentSubscription`: `consumers` (default 1) consumers on the harness-created group `groupName` of
    /// `$ce-<category>`, acking each event on receipt. Warmup uses group `groupName + "w"` on `$ce-<category>w`.
    public static async Task<Trial> RunPersistentSubscription(EffectiveScenario s, Clients clients)
    {
        string group = s.GroupName!;
        var payloads = MakePayloads(s);
        int consumers = Math.Max(s.Consumers ?? 1, 1);

        if (s.WarmupSeconds > 0)
        {
            Log.Info("warmup");
            var warmup = Names.Warmup(s);
            var warmupBoard = new DeliveryBoard(s);
            var warmupReaders = await PersistentConsumers.Start(clients.PersistentSubscriptions, warmup.CategoryStream, group + "w", consumers, warmupBoard);
            await WriterWindow(s, clients.Streams, payloads, warmup, s.WarmupSeconds, warmupBoard);
            await warmupReaders.Stop();
        }

        Log.Info("measure");
        var measured = Names.Measured(s);
        var board = new DeliveryBoard(s);
        // The measured group is first touched here, right before the window starts.
        var readers = await PersistentConsumers.Start(clients.PersistentSubscriptions, measured.CategoryStream, group, consumers, board);
        Log.MarkMeasureStart();
        var window = await WriterWindow(s, clients.Streams, payloads, measured, s.MeasureSeconds, board);
        var deliveries = board.Snapshot();
        // Stay connected (outside the CPU window) so the last acks reach the server and get checkpointed: an ack still
        // in transit when the connection closes is lost, and the orchestrator reads acknowledged progress after exit.
        await Task.Delay(TimeSpan.FromSeconds(PersistentAckSettleSeconds));
        int acks = await readers.Stop();
        return new Trial(window.Recorder, window.Cpu, s.MeasureSeconds,
            new Validation(window.Appended, deliveries.Unique, deliveries.SizesOk),
            AckEnqueued: acks, UniqueDeliveries: deliveries.Unique, Redeliveries: deliveries.Redeliveries);
    }

    /// Consumers of one persistent subscription group, each reading on its own task.
    sealed class PersistentConsumers
    {
        readonly List<KurrentDBPersistentSubscriptionsClient.PersistentSubscriptionResult> _subscriptions = [];
        readonly List<Task> _readers = [];
        readonly CancellationTokenSource _stop = new();
        int _acks;

        /// Connects `count` consumers with the client's default options and returns once the server confirmed each
        /// subscription (the Swift SDK's `subscribe()` likewise returns a started subscription).
        public static async Task<PersistentConsumers> Start(KurrentDBPersistentSubscriptionsClient client, string stream, string group, int count, DeliveryBoard board)
        {
            var consumers = new PersistentConsumers();
            var confirmations = new List<Task>();
            for (int c = 0; c < count; c++)
            {
                var subscription = client.SubscribeToStream(stream, group, cancellationToken: consumers._stop.Token);
                var confirmed = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
                consumers._subscriptions.Add(subscription);
                confirmations.Add(confirmed.Task);
                consumers._readers.Add(Task.Run(() => consumers.Read(subscription, stream, group, board, confirmed)));
            }
            var all = Task.WhenAll(confirmations);
            if (await Task.WhenAny(all, Task.Delay(TimeSpan.FromSeconds(60))) != all)
                throw new TimeoutException($"persistent subscription {stream}/{group} was not confirmed within 60 s");
            await all; // rethrows a consumer's subscription error
            return consumers;
        }

        async Task Read(KurrentDBPersistentSubscriptionsClient.PersistentSubscriptionResult subscription, string stream, string group, DeliveryBoard board, TaskCompletionSource confirmed)
        {
            try
            {
                await foreach (var message in subscription.Messages.WithCancellation(_stop.Token).ConfigureAwait(false))
                {
                    switch (message)
                    {
                        case PersistentSubscriptionMessage.SubscriptionConfirmation:
                            confirmed.TrySetResult();
                            break;
                        case PersistentSubscriptionMessage.Event e:
                            board.Receive(e.ResolvedEvent);
                            await subscription.Ack(e.ResolvedEvent).ConfigureAwait(false);
                            Interlocked.Increment(ref _acks);
                            break;
                        case PersistentSubscriptionMessage.NotFound:
                            throw new InvalidOperationException($"persistent subscription group {stream}/{group} not found");
                    }
                }
                confirmed.TrySetException(new InvalidOperationException($"persistent subscription {stream}/{group} ended"));
            }
            catch (Exception e)
            {
                confirmed.TrySetException(e);
                if (!_stop.IsCancellationRequested) Log.Info($"persistent subscription on {stream}/{group} ended: {e.Message}");
            }
        }

        /// Stops reading and returns the acks handed to the client.
        public async Task<int> Stop()
        {
            int total = Volatile.Read(ref _acks);
            _stop.Cancel();
            foreach (var subscription in _subscriptions) await subscription.DisposeAsync();
            await Task.WhenAll(_readers);
            return total;
        }
    }

    // MARK: Catch-up subscription

    /// Upper bound on phase 1: at least two minutes, or one millisecond per corpus event (1,000 events/s).
    static TimeSpan CatchUpLimit(int corpus) => TimeSpan.FromSeconds(Math.Max(120, corpus / 1000));

    /// `catchUp`: warmup exercises the live path on `$ce-<category>w`. Phase 1 times a catch-up subscription from the
    /// start of `$ce-<category>` (links resolved) until `catchUpExpectedEvents` events have arrived. Phase 2 keeps
    /// that subscription and runs the open-loop writer into the same category; the corpus is not counted in phase 2.
    public static async Task<Trial> RunCatchUp(EffectiveScenario s, Clients clients)
    {
        int corpus = s.CatchUpExpectedEvents ?? 0;
        var payloads = MakePayloads(s);

        if (s.WarmupSeconds > 0)
        {
            Log.Info("warmup");
            var warmup = Names.Warmup(s);
            var warmupBoard = new DeliveryBoard(s);
            var warmupReader = await CatchUpReader.Start(clients.Streams, warmup.CategoryStream, 0, warmupBoard);
            await WriterWindow(s, clients.Streams, payloads, warmup, s.WarmupSeconds, warmupBoard);
            await warmupReader.Stop();
        }

        Log.Info($"phase 1: catching up on {corpus} events");
        var measured = Names.Measured(s);
        var board = new DeliveryBoard(s);
        long started = MonoClock.Now();
        var reader = await CatchUpReader.Start(clients.Streams, measured.CategoryStream, corpus, board);
        try
        {
            long? caughtUp = await reader.CorpusReceived(CatchUpLimit(corpus));
            var phase1 = reader.Phase1();
            if (caughtUp is null)
            {
                // The orchestrator fails a catch-up trial whose catchUpSeconds is null; the live phase is skipped.
                Log.Info($"phase 1 received {phase1.Events} of {corpus} events within {CatchUpLimit(corpus).TotalSeconds} s");
                return new Trial(new OutcomeRecorder(), (0, 0), 0,
                    new Validation(corpus, phase1.Events, phase1.SizesOk),
                    UniqueDeliveries: 0, Redeliveries: 0, CatchUpSeconds: null);
            }
            double catchUpSeconds = (caughtUp.Value - started) / 1e9;

            Log.Info("phase 2: measure");
            Log.MarkMeasureStart();
            var window = await WriterWindow(s, clients.Streams, payloads, measured, s.MeasureSeconds, board);
            var deliveries = board.Snapshot();
            return new Trial(window.Recorder, window.Cpu, s.MeasureSeconds,
                new Validation(
                    ExpectedEvents: corpus + window.Appended,
                    ReceivedEvents: phase1.Events + deliveries.Unique,
                    PayloadSizesOk: phase1.SizesOk && deliveries.SizesOk),
                UniqueDeliveries: deliveries.Unique, Redeliveries: deliveries.Redeliveries, CatchUpSeconds: catchUpSeconds);
        }
        finally
        {
            await reader.Stop();
        }
    }

    /// One catch-up subscription: the first `corpus` events are phase 1 (counted and size-checked), every later event
    /// goes to the delivery board.
    sealed class CatchUpReader
    {
        readonly object _gate = new();
        readonly CancellationTokenSource _stop = new();
        readonly TaskCompletionSource _caughtUp = new(TaskCreationOptions.RunContinuationsAsynchronously);
        KurrentDBClient.StreamSubscriptionResult? _subscription;
        Task? _reader;
        int _events;
        bool _sizesOk = true;
        long? _caughtUpAt;

        readonly TaskCompletionSource _confirmed = new(TaskCreationOptions.RunContinuationsAsynchronously);

        /// Subscribes and returns once the server confirmed the subscription; a subscription that fails before that
        /// throws here, so the driver exits non-zero at once (the Swift SDK's `subscribe()` throws the same way) instead
        /// of waiting out the phase-1 limit. Errors after the confirmation are logged, as in the Swift driver.
        public static async Task<CatchUpReader> Start(KurrentDBClient client, string stream, int corpus, DeliveryBoard board)
        {
            var reader = new CatchUpReader();
            if (corpus == 0)
            {
                reader._caughtUpAt = MonoClock.Now();
                reader._caughtUp.TrySetResult();
            }
            reader._subscription = client.SubscribeToStream(stream, FromStream.Start, resolveLinkTos: true, cancellationToken: reader._stop.Token);
            reader._reader = Task.Run(() => reader.Read(reader._subscription, stream, corpus, board));
            var confirmed = reader._confirmed.Task;
            if (await Task.WhenAny(confirmed, Task.Delay(TimeSpan.FromSeconds(60))) != confirmed)
            {
                await reader.Stop();
                throw new TimeoutException($"catch-up subscription on {stream} was not confirmed within 60 s");
            }
            if (confirmed.IsFaulted)
            {
                await reader.Stop();
                await confirmed; // rethrows the subscription's error
            }
            return reader;
        }

        async Task Read(KurrentDBClient.StreamSubscriptionResult subscription, string stream, int corpus, DeliveryBoard board)
        {
            try
            {
                await foreach (var message in subscription.Messages.WithCancellation(_stop.Token).ConfigureAwait(false))
                {
                    if (message is StreamMessage.SubscriptionConfirmation) _confirmed.TrySetResult();
                    if (message is not StreamMessage.Event e) continue;
                    _confirmed.TrySetResult(); // an event implies a live subscription
                    bool inCorpus;
                    lock (_gate)
                    {
                        inCorpus = _events < corpus;
                        if (inCorpus)
                        {
                            _events++;
                            if (!board.HasExpectedSizes(e.ResolvedEvent)) _sizesOk = false;
                            if (_events == corpus)
                            {
                                _caughtUpAt = MonoClock.Now();
                                _caughtUp.TrySetResult();
                            }
                        }
                    }
                    if (!inCorpus) board.Receive(e.ResolvedEvent);
                }
                _confirmed.TrySetException(new InvalidOperationException($"catch-up subscription on {stream} ended"));
            }
            catch (Exception e)
            {
                if (!_confirmed.TrySetException(e) && !_stop.IsCancellationRequested)
                    Log.Info($"catch-up subscription on {stream} ended: {e.Message}");
            }
        }

        /// The instant the last corpus event arrived, or null if it did not arrive within `limit`.
        public async Task<long?> CorpusReceived(TimeSpan limit)
        {
            await Task.WhenAny(_caughtUp.Task, Task.Delay(limit));
            lock (_gate) return _caughtUpAt;
        }

        public (int Events, bool SizesOk) Phase1()
        {
            lock (_gate) return (_events, _sizesOk);
        }

        public async Task Stop()
        {
            _stop.Cancel();
            if (_subscription is not null) await _subscription.DisposeAsync();
            if (_reader is not null) await _reader;
        }
    }

    // MARK: Writer and deliveries

    /// The open-loop writer: operation i appends event i and completes at the instant the receiving callback stamped
    /// for its first receipt.
    static async Task<(OutcomeRecorder Recorder, (double User, double System) Cpu, int Appended)> WriterWindow(
        EffectiveScenario s, KurrentDBClient client, PayloadFactory payloads, Names names, double seconds, DeliveryBoard board)
    {
        int appended = 0;
        ulong seed = s.Seed;
        int streamCount = s.StreamCount;
        var (recorder, cpu) = await MeasuredWindow(s.OpenLoop(seconds), (i, ct) =>
        {
            string stream = names.Stream(seed, i, streamCount);
            var events = OperationEvents(payloads, 1, i);
            return board.Delivery(i, ct, () => _ = Append());

            // Started once the receipt is awaited, so the receipt can complete the operation before the append's
            // response arrives; a failed append fails the operation. Like the Swift driver's unstructured append task,
            // it is not cancelled with the operation.
            async Task Append()
            {
                try
                {
                    await client.AppendToStreamAsync(stream, StreamState.Any, events).ConfigureAwait(false);
                    Interlocked.Increment(ref appended);
                }
                catch (Exception e)
                {
                    board.Fail(i, e);
                }
            }
        });
        return (recorder, cpu, Volatile.Read(ref appended));
    }
}

/// Matches received events to waiting writer operations by event index k (parsed from the data's `{"i":k,` prefix),
/// and counts unique deliveries, redeliveries and payload sizes (`DeliveryBoard`).
sealed class DeliveryBoard(EffectiveScenario scenario)
{
    readonly object _gate = new();
    readonly Dictionary<int, TaskCompletionSource<long>> _waiters = new();
    /// First receipt instant of every event seen.
    readonly Dictionary<int, long> _seen = new();
    readonly int _eventSize = scenario.EventSize;
    readonly int _metadataSize = scenario.MetadataSize;
    int _redeliveries;
    bool _sizesOk = true;

    public bool HasExpectedSizes(ResolvedEvent e) =>
        e.Event.Data.Length == _eventSize && e.Event.Metadata.Length == _metadataSize;

    /// Records a receipt: the first one of event k completes its waiting operation, later ones are redeliveries. The
    /// receipt instant is stamped here, on the receiving callback, before any hand-off; the operation reports it as its
    /// completion, so resuming the operation's continuation is not part of the latency.
    public void Receive(ResolvedEvent e)
    {
        long receivedAt = MonoClock.Now();
        bool sizesOk = HasExpectedSizes(e);
        int? index = EventIndex(e.Event.Data.Span);
        TaskCompletionSource<long>? waiter = null;
        lock (_gate)
        {
            if (!sizesOk) _sizesOk = false;
            if (index is not int k)
            {
                _sizesOk = false; // not one of ours, or a link that was not resolved
                return;
            }
            if (_seen.ContainsKey(k))
            {
                _redeliveries++;
                return;
            }
            _seen[k] = receivedAt;
            _waiters.Remove(k, out waiter);
        }
        waiter?.TrySetResult(receivedAt); // continuations run asynchronously, off this callback
    }

    /// Waits for the first receipt of event `index` and returns its stamped instant; `start` runs once the waiter is
    /// registered. Throws the append's error if it failed first, or a cancellation when the operation is cancelled
    /// (its deadline passed).
    public async Task<long?> Delivery(int index, CancellationToken cancellationToken, Action start)
    {
        var waiter = new TaskCompletionSource<long>(TaskCreationOptions.RunContinuationsAsynchronously);
        lock (_gate)
        {
            if (_seen.TryGetValue(index, out long receivedAt)) return receivedAt;
            _waiters[index] = waiter;
        }
        start();
        using var registration = cancellationToken.Register(() =>
        {
            lock (_gate) _waiters.Remove(index);
            waiter.TrySetCanceled(cancellationToken);
        });
        return await waiter.Task.ConfigureAwait(false);
    }

    /// The append of event `index` failed: fail its waiting operation.
    public void Fail(int index, Exception error)
    {
        TaskCompletionSource<long>? waiter;
        lock (_gate)
        {
            if (_seen.ContainsKey(index)) return;
            _waiters.Remove(index, out waiter);
        }
        waiter?.TrySetException(error);
    }

    public (int Unique, int Redeliveries, bool SizesOk) Snapshot()
    {
        lock (_gate) return (_seen.Count, _redeliveries, _sizesOk);
    }

    /// k from data starting with `{"i":k,`, or null.
    public static int? EventIndex(ReadOnlySpan<byte> data)
    {
        ReadOnlySpan<byte> prefix = "{\"i\":"u8;
        if (data.Length <= prefix.Length || !data.StartsWith(prefix)) return null;
        long value = 0;
        int digits = 0;
        foreach (byte b in data[prefix.Length..])
        {
            if (b < (byte)'0' || b > (byte)'9') return b == (byte)',' && digits > 0 && value <= int.MaxValue ? (int)value : null;
            value = value * 10 + (b - '0');
            if (++digits > 18) return null;
        }
        return null;
    }
}
