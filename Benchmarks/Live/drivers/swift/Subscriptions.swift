import Foundation
import KurrentDB
import LiveBenchCore
import Synchronization

// Subscription kinds: an in-process open-loop writer appends one event per operation (event index k = operation index)
// to `<streamPrefix>-<pick(i)>`; the operation completes at the subscriber's first receipt of that event. Latency is
// therefore from the append's `min(scheduled, launch)` (runOpenLoop) to the receipt. A failed append fails the
// operation; an event not received by its deadline is a timeout.

// MARK: - Persistent subscription

/// `persistentSubscription`: `consumers` (default 1) consumers on the harness-created group `groupName` of
/// `$ce-<category>`, acking each event on receipt. Warmup uses group `groupName + "w"` on `$ce-<category>w`.
func runPersistentSubscription(_ scenario: EffectiveScenario, client: KurrentDBClient) async throws -> Trial {
    let group = scenario.groupName ?? ""
    let payloads = scenario.makePayloads()
    let consumers = max(scenario.consumers ?? 1, 1)

    if scenario.warmupSeconds > 0 {
        log("warmup")
        let warmup = Names.warmup(scenario)
        let board = DeliveryBoard(scenario)
        let readers = try await PersistentConsumers.start(client, stream: warmup.categoryStream, group: group + "w", count: consumers, board: board)
        _ = await writerWindow(scenario, client: client, payloads: payloads, names: warmup, seconds: scenario.warmupSeconds, board: board)
        readers.stop()
    }

    log("measure")
    let measured = Names.measured(scenario)
    let board = DeliveryBoard(scenario)
    // The measured group is first touched here, right before the window starts.
    let readers = try await PersistentConsumers.start(client, stream: measured.categoryStream, group: group, count: consumers, board: board)
    markMeasureStart()
    let window = await writerWindow(scenario, client: client, payloads: payloads, names: measured, seconds: scenario.measureSeconds, board: board)
    let deliveries = board.snapshot()
    // Stay connected (outside the CPU window) so the last acks reach the server and get checkpointed: an ack still in
    // transit when the connection closes is lost, and the orchestrator reads acknowledged progress after exit.
    try? await Task.sleep(for: .seconds(persistentAckSettleSeconds))
    let acks = readers.stop()
    return Trial(
        recorder: window.recorder, cpu: window.cpu, measuredSeconds: scenario.measureSeconds,
        validation: Validation(expectedEvents: window.appended, receivedEvents: deliveries.unique, payloadSizesOk: deliveries.sizesOk),
        ackEnqueued: acks, uniqueDeliveries: deliveries.unique, redeliveries: deliveries.redeliveries
    )
}

/// Seconds the measured consumers stay connected after the drain (driver contract, "Persistent subscription").
let persistentAckSettleSeconds = 3.0

/// Consumers of one persistent subscription group, each reading on its own task.
private struct PersistentConsumers {
    let readers: [Task<Void, Never>]
    let acks: Counter

    static func start(_ client: KurrentDBClient, stream: String, group: String, count: Int, board: DeliveryBoard) async throws -> PersistentConsumers {
        let acks = Counter()
        var readers: [Task<Void, Never>] = []
        for _ in 0..<count {
            let subscription = try await client.persistentSubscriptions(stream: stream, group: group).subscribe()
            readers.append(Task {
                do {
                    for try await result in subscription.events {
                        board.receive(result.event)
                        try await subscription.ack(readEvents: result.event)
                        acks.increment()
                    }
                } catch {
                    if !Task.isCancelled { log("persistent subscription on \(stream)/\(group) ended: \(error)") }
                }
            })
        }
        return PersistentConsumers(readers: readers, acks: acks)
    }

    /// Stops reading and returns the acks handed to the client. Cancelling a reader ends its `events` iteration; the
    /// subscription's connection closes once nothing references it (see `PersistentSubscriptions.Subscription`).
    @discardableResult
    func stop() -> Int {
        let total = acks.value
        for reader in readers { reader.cancel() }
        return total
    }
}

// MARK: - Catch-up subscription

/// Upper bound on phase 1: at least two minutes, or one millisecond per corpus event (1,000 events/s).
private func catchUpLimit(_ corpus: Int) -> Duration { .seconds(max(120, corpus / 1000)) }

/// `catchUp`: warmup exercises the live path on `$ce-<category>w`. Phase 1 times a catch-up subscription from the start
/// of `$ce-<category>` (links resolved) until `catchUpExpectedEvents` events have arrived. Phase 2 keeps that
/// subscription and runs the open-loop writer into the same category; the corpus is not counted in phase 2.
func runCatchUp(_ scenario: EffectiveScenario, client: KurrentDBClient) async throws -> Trial {
    let corpus = scenario.catchUpExpectedEvents ?? 0
    let payloads = scenario.makePayloads()

    if scenario.warmupSeconds > 0 {
        log("warmup")
        let warmup = Names.warmup(scenario)
        let board = DeliveryBoard(scenario)
        let reader = try await CatchUpReader.start(client, stream: warmup.categoryStream, corpus: 0, board: board)
        _ = await writerWindow(scenario, client: client, payloads: payloads, names: warmup, seconds: scenario.warmupSeconds, board: board)
        reader.stop()
    }

    log("phase 1: catching up on \(corpus) events")
    let measured = Names.measured(scenario)
    let board = DeliveryBoard(scenario)
    let clock = ContinuousClock()
    let started = clock.now
    let reader = try await CatchUpReader.start(client, stream: measured.categoryStream, corpus: corpus, board: board)
    defer { reader.stop() }
    let caughtUp = await reader.corpusReceived(within: catchUpLimit(corpus))
    let phase1 = reader.phase1()
    guard let caughtUp else {
        // The orchestrator fails a catch-up trial whose catchUpSeconds is null; the live phase is skipped.
        log("phase 1 received \(phase1.events) of \(corpus) events within \(catchUpLimit(corpus))")
        return Trial(
            recorder: OutcomeRecorder(), cpu: (0, 0), measuredSeconds: 0,
            validation: Validation(expectedEvents: corpus, receivedEvents: phase1.events, payloadSizesOk: phase1.sizesOk),
            uniqueDeliveries: 0, redeliveries: 0, catchUpSeconds: nil
        )
    }
    let catchUpSeconds = durationSeconds(started.duration(to: caughtUp))

    log("phase 2: measure")
    markMeasureStart()
    let window = await writerWindow(scenario, client: client, payloads: payloads, names: measured, seconds: scenario.measureSeconds, board: board)
    let deliveries = board.snapshot()
    return Trial(
        recorder: window.recorder, cpu: window.cpu, measuredSeconds: scenario.measureSeconds,
        validation: Validation(
            expectedEvents: corpus + window.appended,
            receivedEvents: phase1.events + deliveries.unique,
            payloadSizesOk: phase1.sizesOk && deliveries.sizesOk
        ),
        uniqueDeliveries: deliveries.unique, redeliveries: deliveries.redeliveries, catchUpSeconds: catchUpSeconds
    )
}

/// One catch-up subscription: the first `corpus` events are phase 1 (counted and size-checked), every later event goes
/// to the delivery board.
private final class CatchUpReader: Sendable {
    private struct State {
        var events = 0
        var sizesOk = true
        var caughtUpAt: ContinuousClock.Instant?
        var waiter: CheckedContinuation<Void, Never>?
    }

    private let state = Mutex(State())
    private let subscription: Streams<SpecifiedStream>.Subscription
    private let reader: Mutex<Task<Void, Never>?> = Mutex(nil)

    private init(subscription: Streams<SpecifiedStream>.Subscription) {
        self.subscription = subscription
    }

    static func start(_ client: KurrentDBClient, stream: String, corpus: Int, board: DeliveryBoard) async throws -> CatchUpReader {
        let subscription = try await client.streams(specified: stream).subscribe {
            $0.revision = .start
            $0.resolveLinksEnabled = true
        }
        let reader = CatchUpReader(subscription: subscription)
        let clock = ContinuousClock()
        if corpus == 0 { reader.state.withLock { $0.caughtUpAt = clock.now } }
        let task = Task { [reader] in
            do {
                for try await event in subscription.events {
                    let inCorpus = reader.state.withLock { s -> Bool in
                        guard s.events < corpus else { return false }
                        s.events += 1
                        if !board.hasExpectedSizes(event) { s.sizesOk = false }
                        if s.events == corpus {
                            s.caughtUpAt = clock.now
                            s.waiter?.resume()
                            s.waiter = nil
                        }
                        return true
                    }
                    if !inCorpus { board.receive(event) }
                }
            } catch {
                if !Task.isCancelled { log("catch-up subscription on \(stream) ended: \(error)") }
            }
        }
        reader.reader.withLock { $0 = task }
        return reader
    }

    /// The instant the last corpus event arrived, or nil if it did not arrive within `limit`.
    func corpusReceived(within limit: Duration) async -> ContinuousClock.Instant? {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    let done = self.state.withLock { s -> Bool in
                        if s.caughtUpAt != nil { return true }
                        s.waiter = continuation
                        return false
                    }
                    if done { continuation.resume() }
                }
            }
            group.addTask { try? await Task.sleep(for: limit) }
            await group.next()
            group.cancelAll()
            // Release a waiter still parked (the timeout won).
            state.withLock { s in
                s.waiter?.resume()
                s.waiter = nil
            }
        }
        return state.withLock { $0.caughtUpAt }
    }

    func phase1() -> (events: Int, sizesOk: Bool) {
        state.withLock { ($0.events, $0.sizesOk) }
    }

    func stop() {
        reader.withLock { $0?.cancel() }
        subscription.cancel()
    }
}

// MARK: - Writer and deliveries

/// The open-loop writer: operation *i* appends event *i* and completes at the instant the receiving callback stamped
/// for its first receipt.
private func writerWindow(
    _ scenario: EffectiveScenario, client: KurrentDBClient, payloads: PayloadFactory, names: Names, seconds: Double,
    board: DeliveryBoard
) async -> (recorder: OutcomeRecorder, cpu: (user: Double, system: Double), appended: Int) {
    let appended = Counter()
    let seed = scenario.seed, streamCount = scenario.streamCount
    let (recorder, cpu) = await measuredWindow(scenario.openLoop(seconds: seconds)) { i in
        let stream = client.streams(specified: names.stream(seed: seed, index: i, count: streamCount))
        let events = operationEvents(payloads, batchSize: 1, operation: i)
        return try await board.delivery(of: i) {
            // Started once the receipt is awaited, so the receipt can complete the operation before the append's
            // response arrives; a failed append fails the operation.
            Task {
                do {
                    try await stream.append(events: events) { $0.expectedRevision = .any }
                    appended.increment()
                } catch {
                    board.fail(i, error)
                }
            }
        }
    }
    return (recorder, cpu, appended.value)
}

/// Matches received events to waiting writer operations by event index `k` (parsed from the data's `{"i":k,` prefix),
/// and counts unique deliveries, redeliveries and payload sizes.
final class DeliveryBoard: Sendable {
    struct Snapshot {
        var unique: Int
        var redeliveries: Int
        var sizesOk: Bool
    }

    private struct State {
        var waiters: [Int: CheckedContinuation<ContinuousClock.Instant, Error>] = [:]
        var failed: [Int: Error] = [:]
        var cancelled: Set<Int> = []
        /// First receipt instant of every event seen.
        var seen: [Int: ContinuousClock.Instant] = [:]
        var redeliveries = 0
        var sizesOk = true
    }

    private let state = Mutex(State())
    private let eventSize: Int
    private let metadataSize: Int

    init(_ scenario: EffectiveScenario) {
        eventSize = scenario.eventSize
        metadataSize = scenario.metadataSize
    }

    func hasExpectedSizes(_ event: ReadEvent) -> Bool {
        event.record.data.count == eventSize && event.record.customMetadata.count == metadataSize
    }

    /// Records a receipt: the first one of event `k` completes its waiting operation, later ones are redeliveries.
    /// The receipt instant is stamped here, on the receiving callback, before any hand-off; the operation reports it
    /// as its completion, so resuming the operation's task is not part of the latency.
    func receive(_ event: ReadEvent) {
        let receivedAt = ContinuousClock.now
        let sizesOk = hasExpectedSizes(event)
        let index = Self.eventIndex(event.record.data)
        let waiter = state.withLock { s -> CheckedContinuation<ContinuousClock.Instant, Error>? in
            if !sizesOk { s.sizesOk = false }
            guard let index else {
                s.sizesOk = false // not one of ours, or a link that was not resolved
                return nil
            }
            guard s.seen[index] == nil else {
                s.redeliveries += 1
                return nil
            }
            s.seen[index] = receivedAt
            return s.waiters.removeValue(forKey: index)
        }
        waiter?.resume(returning: receivedAt)
    }

    /// Waits for the first receipt of event `index` and returns its stamped instant; `start` runs once the waiter is
    /// registered. Throws the append's error if it failed first, or `CancellationError` when the operation is cancelled
    /// (its deadline passed).
    func delivery(of index: Int, start: () -> Void) async throws -> ContinuousClock.Instant {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ContinuousClock.Instant, Error>) in
                let registration = state.withLock { s -> Registration in
                    if s.cancelled.remove(index) != nil { return .cancelled }
                    if let error = s.failed.removeValue(forKey: index) { return .failed(error) }
                    if let receivedAt = s.seen[index] { return .delivered(receivedAt) }
                    s.waiters[index] = continuation
                    return .waiting
                }
                switch registration {
                case .waiting:
                    start()
                case .delivered(let receivedAt):
                    continuation.resume(returning: receivedAt)
                case .failed(let error):
                    continuation.resume(throwing: error)
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            let waiter = state.withLock { s -> CheckedContinuation<ContinuousClock.Instant, Error>? in
                guard let waiter = s.waiters.removeValue(forKey: index) else {
                    s.cancelled.insert(index) // cancelled before registering
                    return nil
                }
                return waiter
            }
            waiter?.resume(throwing: CancellationError())
        }
    }

    /// The append of event `index` failed: fail its waiting operation.
    func fail(_ index: Int, _ error: Error) {
        let waiter = state.withLock { s -> CheckedContinuation<ContinuousClock.Instant, Error>? in
            guard s.seen[index] == nil else { return nil }
            guard let waiter = s.waiters.removeValue(forKey: index) else {
                s.failed[index] = error
                return nil
            }
            return waiter
        }
        waiter?.resume(throwing: error)
    }

    func snapshot() -> Snapshot {
        state.withLock { Snapshot(unique: $0.seen.count, redeliveries: $0.redeliveries, sizesOk: $0.sizesOk) }
    }

    /// `k` from data starting with `{"i":k,`, or nil.
    static func eventIndex(_ data: Data) -> Int? {
        let prefix = Array(#"{"i":"#.utf8)
        guard data.count > prefix.count, data.starts(with: prefix) else { return nil }
        var value = 0
        var digits = 0
        for byte in data.dropFirst(prefix.count) {
            guard byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") else {
                return byte == UInt8(ascii: ",") && digits > 0 ? value : nil
            }
            value = value * 10 + Int(byte - UInt8(ascii: "0"))
            digits += 1
            if digits > 18 { return nil }
        }
        return nil
    }
}

/// What registering a delivery waiter found. (File scope: a local enum with payloads here crashes the 6.2 compiler.)
private enum Registration {
    case waiting, delivered(ContinuousClock.Instant), failed(Error), cancelled
}

final class Counter: Sendable {
    private let count = Mutex(0)
    func increment() { count.withLock { $0 += 1 } }
    var value: Int { count.withLock { $0 } }
}

private func durationSeconds(_ d: Duration) -> Double {
    let (seconds, attoseconds) = d.components
    return Double(seconds) + Double(attoseconds) / 1e18
}
