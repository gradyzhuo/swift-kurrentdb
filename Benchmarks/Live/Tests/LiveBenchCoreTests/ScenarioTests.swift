import Foundation
import Testing
@testable import LiveBenchCore

func configURL(_ name: String, filePath: String = #filePath) -> URL {
    URL(fileURLWithPath: filePath)
        .deletingLastPathComponent() // LiveBenchCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // Live
        .appendingPathComponent("config")
        .appendingPathComponent(name)
}

@Suite("Scenario")
struct ScenarioTests {
    @Test func cellsFileDecodes() throws {
        let cells = try loadCells(from: configURL("cells.json"))
        #expect(cells.contains { $0.id == "append-latency-300-tls" && $0.tier == .headline && $0.rounds >= 5 })
        #expect(cells.filter { $0.kind == .rebuild && $0.tier == .headline }.compactMap(\.streamLength).sorted() == [10, 100, 1000, 10000])
        #expect(cells.allSatisfy { $0.tier == .headline ? $0.rounds >= 5 : $0.rounds >= 3 })
    }

    @Test func cellIdsAreUniqueAndFollowThePattern() throws {
        let cells = try loadCells(from: configURL("cells.json"))
        #expect(Set(cells.map(\.id)).count == cells.count)
        #expect(cells.allSatisfy { $0.id.hasSuffix("-\($0.eventSize)-\($0.tls ? "tls" : "notls")") || $0.id.contains("-L") })
    }

    @Test func headlineRatesMatchTheFixedTable() throws {
        let cells = try loadCells(from: configURL("cells.json"))
        func rates(_ id: String) -> [Double]? { cells.first { $0.id == id }?.rates }
        #expect(rates("append-latency-300-tls") == [250, 500, 1000, 2000, 4000, 8000])
        #expect(rates("append-throughput-300-tls") == [20, 50, 100, 200, 400])
        #expect(rates("rebuild-300-tls-L10000") == [1, 2, 8])
        #expect(rates("persistent-subscription-300-tls") == [250, 1000, 4000])
        #expect(rates("catch-up-300-tls") == [250, 1000])
        #expect(rates("append-latency-1024-tls") == [500, 2000])
    }

    @Test func fixturesHaveDefaults() {
        #expect(Cell.fixture().kind == .appendLatency)
        #expect(EffectiveScenario.fixture(kind: .catchUp).kind == .catchUp)
    }
}
