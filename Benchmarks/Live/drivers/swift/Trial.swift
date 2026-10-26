import Foundation
import KurrentDB
import LiveBenchCore
import Synchronization

/// What a kind's run produced; turned into `result.json` by `result(for:)`.
struct Trial {
    var recorder: OutcomeRecorder
    var cpu: (user: Double, system: Double)
    var measuredSeconds: Double
    var validation: Validation
    var ackEnqueued: Int? = nil
    var uniqueDeliveries: Int? = nil
    var redeliveries: Int? = nil
    var catchUpSeconds: Double? = nil

    func result(for scenario: EffectiveScenario) -> TrialResult {
        TrialResult(
            client: "swift", cellId: scenario.cellId, targetRate: scenario.rate, timing: .scheduled,
            scheduled: recorder.scheduled, succeeded: recorder.succeeded, failed: recorder.failed,
            dropped: recorder.dropped, timedOut: recorder.timedOut,
            measuredSeconds: measuredSeconds, cpuUserSeconds: cpu.user, cpuSystemSeconds: cpu.system,
            maxRssBytes: ProcessUsage.current().maxRss,
            ackEnqueued: ackEnqueued, uniqueDeliveries: uniqueDeliveries, redeliveries: redeliveries,
            catchUpSeconds: catchUpSeconds, validation: validation
        )
    }
}

/// Names a phase works on: the measured ones, or the warmup ones (`streamPrefix + "w"`, `category + "w"`).
struct Names {
    var streamPrefix: String
    var category: String

    static func measured(_ s: EffectiveScenario) -> Names { Names(streamPrefix: s.streamPrefix, category: s.category) }
    static func warmup(_ s: EffectiveScenario) -> Names { Names(streamPrefix: s.streamPrefix + "w", category: s.category + "w") }

    /// `<streamPrefix>-<n>` for the seeded pick of operation `index` among `count` streams.
    func stream(seed: UInt64, index: Int, count: Int) -> String {
        "\(streamPrefix)-\(SeededDraw.pick(seed: seed, index: index, count: count))"
    }

    var categoryStream: String { "$ce-\(category)" }
}

extension EffectiveScenario {
    func openLoop(seconds: Double) -> OpenLoopConfig {
        OpenLoopConfig(
            rate: rate,
            duration: .seconds(seconds),
            inFlightCap: inFlightCap,
            deadline: .milliseconds(deadlineMillis),
            drain: .seconds(drainSeconds)
        )
    }

    var payloads: PayloadFactory { PayloadFactory(dataSize: eventSize, metadataSize: metadataSize, seed: seed) }

    /// Operations a window of `seconds` schedules (an upper bound: the loop stops at the window's end).
    func operationCount(seconds: Double) -> Int { Int((rate * seconds).rounded(.up)) + 1 }
}

/// Event `index` of the contract's payload layout: type `BenchEvent`, JSON data and metadata of the scenario's sizes.
func benchEvent(_ payloads: PayloadFactory, index: Int) -> EventData {
    EventData(eventType: "BenchEvent", data: payloads.data(index: index), contentType: .json, customMetadata: payloads.metadata(index: index))
}

/// Runs one open-loop window and measures the process CPU it used (from its start to the end of its drain).
func measuredWindow(
    _ config: OpenLoopConfig,
    operation: @escaping @Sendable (Int) async throws -> Void
) async -> (recorder: OutcomeRecorder, cpu: (user: Double, system: Double)) {
    let before = ProcessUsage.current()
    let recorder = await runOpenLoop(config, operation: operation)
    let after = ProcessUsage.current()
    return (recorder, (after.user - before.user, after.system - before.system))
}

/// Builds each operation's events ahead of its due instant on a background task, so generating seeded payload bytes
/// (one splitmix64 step per filler byte) is not part of the timed operation. Keeps at most `lookahead` operations
/// ahead of the latest one taken; an operation whose events are not ready yet builds them itself.
final class PreparedEvents: Sendable {
    private struct State {
        var ready: [Int: [EventData]] = [:]
        var nextNeeded = 0
    }

    private let state = Mutex(State())
    private let build: @Sendable (Int) -> [EventData]
    private let lookahead: Int
    private let producer: Mutex<Task<Void, Never>?> = Mutex(nil)

    init(count: Int, lookahead: Int, build: @escaping @Sendable (Int) -> [EventData]) {
        self.build = build
        self.lookahead = lookahead
        let task = Task { [weak self] in
            for index in 0..<count {
                while true {
                    guard let self, !Task.isCancelled else { return }
                    if self.state.withLock({ index - $0.nextNeeded <= lookahead }) { break }
                    try? await Task.sleep(for: .milliseconds(2))
                }
                let events = build(index)
                guard let self else { return }
                self.state.withLock { s in
                    // Already taken (the operation built its own): nobody will ask for it.
                    if index >= s.nextNeeded { s.ready[index] = events }
                }
            }
        }
        producer.withLock { $0 = task }
    }

    /// The events of operation `index`, prepared if available, built now otherwise.
    func take(_ index: Int) -> [EventData] {
        let prepared = state.withLock { s -> [EventData]? in
            s.nextNeeded = max(s.nextNeeded, index + 1)
            let events = s.ready.removeValue(forKey: index)
            // Dropped operations never take theirs: forget everything well behind the schedule.
            if s.ready.count > 2 * lookahead {
                let floor = s.nextNeeded - lookahead
                s.ready = s.ready.filter { $0.key >= floor }
            }
            return events
        }
        return prepared ?? build(index)
    }

    /// Stops the producer and frees what it prepared.
    func stop() {
        producer.withLock { $0?.cancel() }
        state.withLock { $0.ready.removeAll() }
    }

    deinit { producer.withLock { $0?.cancel() } }
}

extension PreparedEvents {
    /// Events of operation `i` = event indices `i * batchSize ..< (i + 1) * batchSize`, for a window of `seconds`.
    convenience init(_ scenario: EffectiveScenario, seconds: Double) {
        let payloads = scenario.payloads
        let batchSize = scenario.batchSize
        self.init(
            count: scenario.operationCount(seconds: seconds),
            lookahead: max(64, Int(scenario.rate / 2)) // about half a second of operations
        ) { i in
            (0..<batchSize).map { j in benchEvent(payloads, index: i * batchSize + j) }
        }
    }
}
