import Foundation
import LiveBenchCore
@testable import LiveOrchestrator
import Testing

@Suite("Resource budget")
struct BudgetTests {
    @Test func perEventBytesAreDataPlusMetadataPlusDocumentedOverhead() {
        // Measured on kurrentplatform/kurrentdb:26.2.3 (see Budget.swift): log bytes per event, link events included,
        // were 911 for a 300 B event and 4716 for a 4096 B one (each with 60 B metadata): overhead about 551-560 B.
        #expect(Budget.perEventBytes(eventSize: 300) == 300 + 60 + 640)
        #expect(Budget.perEventBytes(eventSize: 4096) == 4096 + 60 + 640)
    }

    @Test func seedSizesFollowTheSeededEventCounts() {
        let fixed = Budget.databaseFixedBytes
        // Append, persistent subscription: nothing seeded, only the empty database.
        #expect(Budget.seedBytes(.fixture(kind: .appendLatency)) == fixed)
        // Rebuild: 100 measured + 100 warmup streams of L events.
        #expect(Budget.seedBytes(.fixture(kind: .rebuild, streamLength: 10000)) == fixed + 2_000_000 * 1000)
        // Catch-up: the 1,000,000-event corpus.
        #expect(Budget.seedBytes(.fixture(kind: .catchUp)) == fixed + 1_000_000 * 1000)
        #expect(Budget.seedBytes(.fixture(kind: .catchUp, eventSize: 4096)) == fixed + 1_000_000 * 4796)
    }

    @Test func fourKBCatchUpReducesCorpusToFit() {
        // Free 6 GB - 2 GB reserve - 22.8 MB of trial writes (the fixture's top rate, 50 events/s for 95 s at 4796 B)
        // = 3.977e9; halved for the snapshot copy and minus 350 MB fixed = 1.639e9 bytes = 341,8xx events, rounded down.
        let decision = Budget.check(freeBytes: 6_000_000_000, cell: .fixture(kind: .catchUp, eventSize: 4096))
        #expect(decision == .reduceCorpus(to: 341_000))
        guard case let .reduceCorpus(to: corpus) = decision else { return }
        // The reduced corpus really fits, and one more thousand would not.
        func required(_ events: Int) -> Int64 {
            2 * (Budget.databaseFixedBytes + Int64(events) * Budget.perEventBytes(eventSize: 4096))
                + Budget.trialWriteBytes(.fixture(kind: .catchUp, eventSize: 4096)) + Budget.reserveBytes
        }
        #expect(required(corpus) <= 6_000_000_000)
        #expect(required(corpus + 1000) > 6_000_000_000)
    }

    @Test func plentyOfDiskIsOk() {
        #expect(Budget.check(freeBytes: 14_000_000_000, cell: .fixture(kind: .catchUp, eventSize: 4096)) == .ok)
        #expect(Budget.check(freeBytes: 14_000_000_000, cell: .fixture(kind: .rebuild, streamLength: 10000, tier: .headline)) == .ok)
    }

    @Test func tooLittleDiskRefusesWithAReason() {
        guard case let .refuse(reason) = Budget.check(freeBytes: 1_000_000_000, cell: .fixture(kind: .catchUp, eventSize: 300)) else {
            Issue.record("expected refuse")
            return
        }
        #expect(!reason.isEmpty)
        // A rebuild cell cannot shrink: refused rather than reduced.
        if case .refuse = Budget.check(freeBytes: 5_000_000_000, cell: .fixture(kind: .rebuild, streamLength: 10000)) {} else {
            Issue.record("rebuild L10000 must be refused at 5 GB")
        }
    }

    @Test func headlineRebuildL10000FitsTheJobLimit() {
        let minutes = Budget.estimatedMinutes(.fixture(kind: .rebuild, streamLength: 10000, tier: .headline), clients: 3)
        #expect(minutes <= Budget.jobLimitMinutes)
        #expect(minutes <= 330)
    }

    @Test func trialTimeIsRestartPlusWarmupMeasureAndDrain() {
        // 20 + 30 + 60 + 5 = 115 s per trial; fixture rates [20, 50], 5 rounds, 2 clients = 20 trials.
        let cell = Cell.fixture(kind: .appendLatency)
        let expected = (20 * 115.0 + Budget.oneTimeSetupSeconds) / 60
        #expect(abs(Budget.estimatedMinutes(cell, clients: 2) - expected) < 1e-9)
    }

    @Test func seedingTimeIsAddedOnce() {
        let none = Budget.estimatedMinutes(.fixture(kind: .appendLatency), clients: 1)
        let rebuild = Budget.estimatedMinutes(.fixture(kind: .rebuild, streamLength: 1000), clients: 1)
        #expect(abs((rebuild - none) - Double(200_000) / Budget.seedEventsPerSecond / 60) < 1e-9)
    }

    @Test func everyConfiguredCellFitsTheJobAndAFreshRunnerDisk() throws {
        let cells = try loadCells(from: livePackageDirectory.appendingPathComponent("config/cells.json"))
        #expect(!cells.isEmpty)
        for cell in cells {
            #expect(Budget.estimatedMinutes(cell, clients: 3) <= Budget.jobLimitMinutes, "\(cell.id) exceeds the job limit")
            #expect(Budget.check(freeBytes: Budget.githubRunnerFreeBytes, cell: cell) != .refuse(reason: ""), "\(cell.id)")
            if case let .refuse(reason) = Budget.check(freeBytes: Budget.githubRunnerFreeBytes, cell: cell) {
                Issue.record("\(cell.id) refused on a runner: \(reason)")
            }
        }
    }
}
