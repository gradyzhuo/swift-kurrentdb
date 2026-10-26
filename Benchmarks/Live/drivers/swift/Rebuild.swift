import Foundation
import KurrentDB
import LiveBenchCore
import Synchronization

/// `rebuild`: operation *i* reads one whole stream forward from the start (`rebuildStreams[pick(i)]`; warmup reads
/// `<streamPrefix>w-<pick(i)>`) through a lazy read, JSON-decoding every event. A read that does not return exactly
/// `streamLength` events is a failure.
func runRebuild(_ scenario: EffectiveScenario, client: KurrentDBClient) async -> Trial {
    let streams = scenario.rebuildStreams ?? []
    if scenario.warmupSeconds > 0 {
        log("warmup")
        let warmup = Names.warmup(scenario)
        _ = await rebuildWindow(scenario, client: client, seconds: scenario.warmupSeconds, tally: RebuildTally()) { i in
            warmup.stream(seed: scenario.seed, index: i, count: streams.count)
        }
    }
    log("measure")
    let tally = RebuildTally()
    let (recorder, cpu) = await rebuildWindow(scenario, client: client, seconds: scenario.measureSeconds, tally: tally) { i in
        streams[SeededDraw.pick(seed: scenario.seed, index: i, count: streams.count)]
    }
    let length = scenario.streamLength ?? 0
    let t = tally.snapshot()
    // Seeded count (hard): reads that returned the wrong number of events show up as received != expected.
    return Trial(
        recorder: recorder, cpu: cpu, measuredSeconds: scenario.measureSeconds,
        validation: Validation(
            expectedEvents: (recorder.succeeded + t.shortReads) * length,
            receivedEvents: recorder.succeeded * length + t.shortReadEvents,
            payloadSizesOk: t.sizesOk
        )
    )
}

private struct RebuildMismatch: Error {
    let events: Int
}

/// Measure-window bookkeeping that the outcome counters cannot carry.
private final class RebuildTally: Sendable {
    struct Snapshot {
        var shortReads = 0
        var shortReadEvents = 0
        var sizesOk = true
    }

    private let state = Mutex(Snapshot())

    func record(events: Int, expected: Int, sizesOk: Bool) {
        state.withLock { s in
            if !sizesOk { s.sizesOk = false }
            if events != expected {
                s.shortReads += 1
                s.shortReadEvents += events
            }
        }
    }

    func snapshot() -> Snapshot { state.withLock { $0 } }
}

private func rebuildWindow(
    _ scenario: EffectiveScenario, client: KurrentDBClient, seconds: Double, tally: RebuildTally,
    stream: @escaping @Sendable (Int) -> String
) async -> (recorder: OutcomeRecorder, cpu: (user: Double, system: Double)) {
    let length = scenario.streamLength ?? 0
    let eventSize = scenario.eventSize, metadataSize = scenario.metadataSize
    return await measuredWindow(scenario.openLoop(seconds: seconds)) { i in
        var events = 0
        var sizesOk = true
        for try await response in client.streams(specified: stream(i)).read().lazy {
            let record = try response.event.record
            _ = try JSONSerialization.jsonObject(with: record.data)
            if record.data.count != eventSize || record.customMetadata.count != metadataSize { sizesOk = false }
            events += 1
        }
        tally.record(events: events, expected: length, sizesOk: sizesOk)
        if events != length { throw RebuildMismatch(events: events) }
    }
}
