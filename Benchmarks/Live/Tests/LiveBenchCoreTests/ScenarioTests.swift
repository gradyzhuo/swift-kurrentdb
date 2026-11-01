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
        #expect(cells.filter { $0.kind == .rebuild && $0.tier == .headline }.compactMap(\.streamLength).sorted() == [10, 100, 1000])
        #expect(cells.first { $0.id == "rebuild-300-tls-L10000" }?.tier == .appendix)
        // One round above the tier minimum (5 headline, 3 appendix), for the tolerated unsustained round.
        #expect(cells.allSatisfy { $0.tier == .headline ? $0.rounds == 6 : $0.rounds == 4 })
    }

    @Test func cellIdsAreUniqueAndFollowThePattern() throws {
        let cells = try loadCells(from: configURL("cells.json"))
        #expect(Set(cells.map(\.id)).count == cells.count)
        let slugs: [ScenarioKind: String] = [
            .appendLatency: "append-latency", .appendThroughput: "append-throughput", .rebuild: "rebuild",
            .persistentSubscription: "persistent", .catchUp: "catch-up",
        ]
        for c in cells {
            let expected = "\(slugs[c.kind]!)-\(c.eventSize)-\(c.tls ? "tls" : "notls")"
                + (c.streamLength.map { "-L\($0)" } ?? "")
                + (c.consumers.map { "-c\($0)" } ?? "")
            #expect(c.id == expected)
        }
    }

    @Test func multiConsumerAppendixCellDecodes() throws {
        let cells = try loadCells(from: configURL("cells.json"))
        let c = try #require(cells.first { $0.id == "persistent-300-tls-c4" })
        #expect(c.consumers == 4)
        #expect(c.kind == .persistentSubscription && c.tier == .appendix && c.tls && c.eventSize == 300)
        #expect(c.rates == [250, 400] && c.rounds == 4)
        #expect(cells.first { $0.id == "persistent-300-tls" }?.consumers == nil)
    }

    @Test func headlineRatesMatchTheFixedTable() throws {
        let cells = try loadCells(from: configURL("cells.json"))
        func rates(_ id: String) -> [Double]? { cells.first { $0.id == id }?.rates }
        #expect(rates("append-latency-300-tls") == [100, 250, 500, 650])
        #expect(rates("append-throughput-300-tls") == [20, 50, 80, 110])
        #expect(rates("rebuild-300-tls-L10") == [100, 500, 1200])
        #expect(rates("rebuild-300-tls-L100") == [50, 200, 500])
        #expect(rates("rebuild-300-tls-L1000") == [5, 20, 50])
        #expect(rates("rebuild-300-tls-L10000") == [1, 2])
        #expect(rates("persistent-300-tls") == [100, 250, 400])
        #expect(rates("catch-up-300-tls") == [250, 500])
        #expect(rates("append-latency-1024-tls") == [250, 500])
    }

    @Test func fixturesHaveDefaults() {
        #expect(Cell.fixture().kind == .appendLatency)
        #expect(EffectiveScenario.fixture(kind: .catchUp).kind == .catchUp)
    }
}
