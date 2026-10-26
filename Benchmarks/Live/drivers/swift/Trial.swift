import Foundation
import KurrentDB
import LiveBenchCore

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

    /// Precomputes the seeded filler pools; call once per run, before warmup.
    func makePayloads() -> PayloadFactory { PayloadFactory(dataSize: eventSize, metadataSize: metadataSize, seed: seed) }
}

/// Event `index` of the contract's payload layout: type `BenchEvent`, JSON data and metadata of the scenario's sizes.
/// Built inline on the operation path from the factory's precomputed pools (two small copies per event).
func benchEvent(_ payloads: PayloadFactory, index: Int) -> EventData {
    EventData(eventType: "BenchEvent", data: payloads.data(index: index), contentType: .json, customMetadata: payloads.metadata(index: index))
}

/// The `batchSize` events of operation `i`: indices `i * batchSize ..< (i + 1) * batchSize`.
func operationEvents(_ payloads: PayloadFactory, batchSize: Int, operation i: Int) -> [EventData] {
    (0..<batchSize).map { j in benchEvent(payloads, index: i * batchSize + j) }
}

/// Runs one open-loop window and measures the process CPU it used (from its start to the end of its drain).
/// The operation may return the instant it really completed (a subscription receipt); nil means when it returns.
func measuredWindow(
    _ config: OpenLoopConfig,
    operation: @escaping @Sendable (Int) async throws -> ContinuousClock.Instant?
) async -> (recorder: OutcomeRecorder, cpu: (user: Double, system: Double)) {
    let before = ProcessUsage.current()
    let recorder = await runOpenLoop(config, clock: ContinuousClock(), operation: operation)
    let after = ProcessUsage.current()
    return (recorder, (after.user - before.user, after.system - before.system))
}
