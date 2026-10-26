import KurrentDB
import LiveBenchCore

/// `appendLatency` / `appendThroughput`: operation *i* appends `batchSize` events (indices `i * batchSize + j`) in one
/// call to `<streamPrefix>-<pick(i)>` with expected revision any.
func runAppend(_ scenario: EffectiveScenario, client: KurrentDBClient) async -> Trial {
    let payloads = scenario.makePayloads()
    if scenario.warmupSeconds > 0 {
        log("warmup")
        _ = await appendWindow(scenario, client: client, payloads: payloads, names: .warmup(scenario), seconds: scenario.warmupSeconds)
    }
    log("measure")
    markMeasureStart()
    let (recorder, cpu) = await appendWindow(scenario, client: client, payloads: payloads, names: .measured(scenario), seconds: scenario.measureSeconds)
    // Informational for append kinds: every succeeded operation is an acknowledged append of `batchSize` events.
    let events = recorder.succeeded * scenario.batchSize
    let sizesOk = payloads.data(index: 0).count == scenario.eventSize
        && payloads.metadata(index: 0).count == scenario.metadataSize
    return Trial(
        recorder: recorder, cpu: cpu, measuredSeconds: scenario.measureSeconds,
        validation: Validation(expectedEvents: events, receivedEvents: events, payloadSizesOk: sizesOk)
    )
}

private func appendWindow(
    _ scenario: EffectiveScenario, client: KurrentDBClient, payloads: PayloadFactory, names: Names, seconds: Double
) async -> (recorder: OutcomeRecorder, cpu: (user: Double, system: Double)) {
    let seed = scenario.seed, streamCount = scenario.streamCount, batchSize = scenario.batchSize
    return await measuredWindow(scenario.openLoop(seconds: seconds)) { i in
        let stream = names.stream(seed: seed, index: i, count: streamCount)
        try await client.streams(specified: stream).append(events: operationEvents(payloads, batchSize: batchSize, operation: i)) {
            $0.expectedRevision = .any
        }
        return nil
    }
}
