import KurrentDB
import LiveBenchCore

/// `appendLatency` / `appendThroughput`: operation *i* appends `batchSize` events (indices `i * batchSize + j`) in one
/// call to `<streamPrefix>-<pick(i)>` with expected revision any.
func runAppend(_ scenario: EffectiveScenario, client: KurrentDBClient) async -> Trial {
    if scenario.warmupSeconds > 0 {
        log("warmup")
        _ = await appendWindow(scenario, client: client, names: .warmup(scenario), seconds: scenario.warmupSeconds)
    }
    log("measure")
    let (recorder, cpu) = await appendWindow(scenario, client: client, names: .measured(scenario), seconds: scenario.measureSeconds)
    // Informational for append kinds: every succeeded operation is an acknowledged append of `batchSize` events.
    let events = recorder.succeeded * scenario.batchSize
    let sizesOk = scenario.payloads.data(index: 0).count == scenario.eventSize
        && scenario.payloads.metadata(index: 0).count == scenario.metadataSize
    return Trial(
        recorder: recorder, cpu: cpu, measuredSeconds: scenario.measureSeconds,
        validation: Validation(expectedEvents: events, receivedEvents: events, payloadSizesOk: sizesOk)
    )
}

private func appendWindow(
    _ scenario: EffectiveScenario, client: KurrentDBClient, names: Names, seconds: Double
) async -> (recorder: OutcomeRecorder, cpu: (user: Double, system: Double)) {
    let prepared = PreparedEvents(scenario, seconds: seconds)
    defer { prepared.stop() }
    let seed = scenario.seed, streamCount = scenario.streamCount
    return await measuredWindow(scenario.openLoop(seconds: seconds)) { i in
        let stream = names.stream(seed: seed, index: i, count: streamCount)
        try await client.streams(specified: stream).append(events: prepared.take(i)) {
            $0.expectedRevision = .any
        }
    }
}
