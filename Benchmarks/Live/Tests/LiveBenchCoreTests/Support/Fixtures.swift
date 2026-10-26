import Foundation
@testable import LiveBenchCore

extension Cell {
    static func fixture(
        kind: ScenarioKind = .appendLatency,
        eventSize: Int = 300,
        streamLength: Int? = nil,
        tier: Tier = .headline
    ) -> Cell {
        Cell(
            id: "fixture-\(kind.rawValue)-\(eventSize)",
            kind: kind,
            eventSize: eventSize,
            tls: true,
            streamLength: streamLength,
            tier: tier,
            rates: [20, 50],
            rounds: tier == .headline ? 5 : 3
        )
    }
}

extension EffectiveScenario {
    static func fixture(
        kind: ScenarioKind = .appendLatency,
        eventSize: Int = 300,
        rate: Double = 20,
        measureSeconds: Double = 3
    ) -> EffectiveScenario {
        EffectiveScenario(
            cellId: "fixture-\(kind.rawValue)-\(eventSize)",
            kind: kind,
            eventSize: eventSize,
            metadataSize: 60,
            batchSize: kind == .appendThroughput ? 50 : 1,
            streamCount: 100,
            streamPrefix: "bench-fixture",
            category: "benchfixture",
            groupName: kind == .persistentSubscription ? "bench-group" : nil,
            streamLength: kind == .rebuild ? 10 : nil,
            rebuildStreams: kind == .rebuild ? (0..<100).map { "bench-fixture-\($0)" } : nil,
            catchUpExpectedEvents: kind == .catchUp ? 1000 : nil,
            rate: rate,
            warmupSeconds: 1,
            measureSeconds: measureSeconds,
            drainSeconds: 1,
            deadlineMillis: 5000,
            inFlightCap: 256,
            seed: 42
        )
    }
}
