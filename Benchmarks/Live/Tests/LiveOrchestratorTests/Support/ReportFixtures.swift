import Foundation
@testable import LiveBenchCore
@testable import LiveOrchestrator

/// Synthetic cell results for the report, bundle and Bencher tests: every number is made up, nothing runs.
enum ReportFixture {
    /// Headroom well inside every gate.
    static let roomy = HeadroomSample(
        coreBusy: [0.4, 0.5], diskAwaitMillis: 1, diskQueueDepth: 0.5,
        projectionBufferedStart: 0, projectionBufferedEnd: 0, eventsWritten: 15_000
    )
    /// One server core above the 85% gate.
    static let saturated = HeadroomSample(
        coreBusy: [0.97, 0.6], diskAwaitMillis: 1, diskQueueDepth: 0.5,
        projectionBufferedStart: 0, projectionBufferedEnd: 0, eventsWritten: 30_000
    )

    /// One trial: `scheduled = rate * 60`, `lost` of them timed out, the successes split 90/10 between `fast` and
    /// `slow` microseconds. CPU and RSS scale with `cost`.
    static func trial(
        round: Int, rate: Double, driver: String, kind: ScenarioKind = .appendLatency,
        fast: UInt64, slow: UInt64, lost: Int = 0, failedAll: Bool = false, cost: Double = 1,
        headroom: HeadroomSample? = roomy, acked: Int64? = nil, delivered: Int? = nil, error: String? = nil
    ) -> TrialRecord {
        let scheduled = Int(rate * 60)
        let succeeded = failedAll ? 0 : scheduled - lost
        let fastCount = UInt64(Double(succeeded) * 0.9)
        let slowCount = UInt64(succeeded) - fastCount
        var buckets: [[UInt64]] = []
        if fastCount > 0 { buckets.append([fast, fastCount]) }
        if slowCount > 0 { buckets.append([slow, slowCount]) }
        let subscription = kind == .persistentSubscription || kind == .catchUp
        let result = TrialResult(
            client: driver, cellId: "cell", targetRate: rate, timing: driver == "ghz" ? .rpcStart : .scheduled,
            scheduled: scheduled, succeeded: succeeded, failed: failedAll ? scheduled : 0, dropped: 0,
            timedOut: failedAll ? 0 : lost, measuredSeconds: 60,
            cpuUserSeconds: driver == "ghz" ? 0 : 0.002 * Double(scheduled) * cost,
            cpuSystemSeconds: driver == "ghz" ? 0 : 0.0005 * Double(scheduled) * cost,
            maxRssBytes: driver == "ghz" ? 0 : UInt64(60_000_000 * cost),
            ackEnqueued: kind == .persistentSubscription ? succeeded : nil,
            uniqueDeliveries: subscription ? (delivered ?? succeeded) : nil,
            redeliveries: subscription ? 0 : nil,
            catchUpSeconds: kind == .catchUp ? 40 * cost : nil,
            validation: Validation(
                expectedEvents: subscription ? scheduled : succeeded,
                receivedEvents: subscription ? (delivered ?? succeeded) : succeeded,
                payloadSizesOk: true
            )
        )
        var record = TrialRecord(round: round, rate: rate, driver: driver)
        record.result = result
        record.histogram = HistogramFile(buckets: buckets)
        record.headroom = driver == "ghz" ? nil : headroom
        record.serverAckedProgress = kind == .persistentSubscription ? (acked ?? Int64(scheduled)) : nil
        record.error = error
        return record
    }

    static func cell(_ id: String, kind: ScenarioKind = .appendLatency, tier: Tier = .headline, rates: [Double], rounds: Int) -> Cell {
        Cell(id: id, kind: kind, eventSize: 300, tls: true, streamLength: kind == .rebuild ? 100 : nil, tier: tier, rates: rates, rounds: rounds)
    }

    static func metadata(rates: [Double], rounds: Int) -> RunMetadata {
        var metadata = RunMetadata()
        metadata.sdkCommit = "0123456789abcdef0123456789abcdef01234567"
        metadata.swiftToolchain = "swift 6.2"
        metadata.dotnetRuntime = ".NET 8.0.11"
        metadata.kurrentDBClientVersion = "1.6.0"
        metadata.serverImage = "kurrentplatform/kurrentdb:26.2.3"
        metadata.serverImageDigest = "sha256:abc"
        metadata.cpuModel = "Example CPU @ 2.4GHz"
        metadata.runDate = "2026-10-27"
        metadata.scenario = .init(
            rates: rates, rounds: rounds, warmupSeconds: 30, measureSeconds: 60, drainSeconds: 5,
            inFlightCap: 256, deadlineMillis: 5000, seed: 42, smoke: false
        )
        return metadata
    }

    /// Builds a cell where `make(round, rate, driver)` returns each trial (nil skips it).
    static func result(
        _ cell: Cell, drivers: [String] = ["swift", "dotnet"],
        make: (Int, Double, String) -> TrialRecord?
    ) -> CellResult {
        var trials: [TrialRecord] = []
        for round in 0..<cell.rounds {
            for rate in cell.rates {
                for driver in drivers {
                    if let trial = make(round, rate, driver) { trials.append(trial) }
                }
            }
        }
        return CellResult(cell: cell, trials: trials, metadata: metadata(rates: cell.rates, rounds: cell.rounds), abortedReason: nil)
    }

    /// A small, round-dependent wobble so the confidence intervals have width.
    static func wobble(_ round: Int) -> Double { [1.0, 1.04, 0.97, 1.02, 0.99, 1.01][round % 6] }
}

extension CellResult {
    /// Append latency, headroom everywhere. At 500/s Swift times out 2% of its operations, so its p99 is censored.
    static var fixtureWithLosses: CellResult {
        ReportFixture.result(ReportFixture.cell("append-latency-losses", rates: [250, 500], rounds: 5)) { round, rate, driver in
            let w = ReportFixture.wobble(round)
            let swift = driver == "swift"
            return ReportFixture.trial(
                round: round, rate: rate, driver: driver,
                fast: UInt64((swift ? 1100 : 1000) * w), slow: UInt64((swift ? 4000 : 3000) * w),
                lost: swift && rate == 500 ? Int(rate * 60 * 0.02) : 0, cost: swift ? 1.1 * w : 1.0
            )
        }
    }

    /// Every operation of every trial failed.
    static var fixtureAllFailed: CellResult {
        ReportFixture.result(ReportFixture.cell("append-latency-all-failed", rates: [250, 500], rounds: 5)) { round, rate, driver in
            ReportFixture.trial(round: round, rate: rate, driver: driver, fast: 1000, slow: 2000, failedAll: true)
        }
    }

    /// Both clients sustain both steps; at 500/s the server has no headroom (a core above 85%).
    static var fixtureSystemLimited: CellResult {
        ReportFixture.result(ReportFixture.cell("append-latency-system-limited", rates: [250, 500], rounds: 5)) { round, rate, driver in
            let w = ReportFixture.wobble(round)
            return ReportFixture.trial(
                round: round, rate: rate, driver: driver, fast: UInt64(1000 * w), slow: UInt64(3000 * w),
                cost: w, headroom: rate == 500 ? ReportFixture.saturated : ReportFixture.roomy
            )
        }
    }

    /// No headroom sample at all (e.g. a macOS run).
    static var fixtureHeadroomUnavailable: CellResult {
        ReportFixture.result(ReportFixture.cell("append-latency-no-headroom", rates: [250, 500], rounds: 5)) { round, rate, driver in
            let w = ReportFixture.wobble(round)
            return ReportFixture.trial(round: round, rate: rate, driver: driver, fast: UInt64(1000 * w), slow: UInt64(3000 * w), cost: w, headroom: nil)
        }
    }

    /// Append latency with a ghz transport reference that is much faster than both SDKs.
    static var fixtureWithGhz: CellResult {
        ReportFixture.result(ReportFixture.cell("append-latency-ghz", rates: [250, 500], rounds: 5), drivers: ["swift", "dotnet", "ghz"]) { round, rate, driver in
            let w = ReportFixture.wobble(round)
            let base: Double = driver == "ghz" ? 100 : (driver == "swift" ? 1050 : 1000)
            return ReportFixture.trial(round: round, rate: rate, driver: driver, fast: UInt64(base * w), slow: UInt64(base * 3 * w), cost: w)
        }
    }

    /// The cell stopped in round 1 (disk); round 0 is complete.
    static var fixtureAborted: CellResult {
        var result = ReportFixture.result(ReportFixture.cell("append-latency-aborted", rates: [250, 500], rounds: 5)) { round, rate, driver in
            round == 0 ? ReportFixture.trial(round: round, rate: rate, driver: driver, fast: 1000, slow: 3000) : nil
        }
        result.abortedReason = "disk: round 1, rate 250, driver swift needs 900 MB free, 400 MB are"
        return result
    }

    /// Persistent subscription where the .NET client's acknowledged progress falls short at 4000/s, plus a failed
    /// trial whose error carries a local path and a private address.
    static var fixturePersistent: CellResult {
        var result = ReportFixture.result(ReportFixture.cell("persistent-fixture", kind: .persistentSubscription, rates: [250, 4000], rounds: 5)) { round, rate, driver in
            let w = ReportFixture.wobble(round)
            let scheduled = Int64(rate * 60)
            return ReportFixture.trial(
                round: round, rate: rate, driver: driver, kind: .persistentSubscription,
                fast: UInt64(2000 * w), slow: UInt64(6000 * w), cost: driver == "dotnet" ? 1.8 * w : w,
                acked: driver == "dotnet" && rate == 4000 ? scheduled - 1200 : scheduled,
                delivered: driver == "dotnet" && rate == 4000 ? Int(scheduled) - 30 : nil
            )
        }
        var failed = TrialRecord(round: 4, rate: 250, driver: "dotnet")
        failed.error = "driver dotnet exited 1: cannot open /Users/alice/tmp/live/x.json via 10.1.2.3:2113 or /home/bob/work"
        failed.notes = ["headroom unavailable: the driver wrote no LIVE_BENCH_MEASURE_START line on stderr (/Users/alice)"]
        result.trials.removeAll { $0.round == 4 && $0.rate == 250 && $0.driver == "dotnet" }
        result.trials.append(failed)
        return result
    }

    /// Appendix catch-up cell on a reduced corpus.
    static var fixtureCatchUpReduced: CellResult {
        var result = ReportFixture.result(ReportFixture.cell("catch-up-fixture", kind: .catchUp, tier: .appendix, rates: [250, 1000], rounds: 3)) { round, rate, driver in
            let w = ReportFixture.wobble(round)
            return ReportFixture.trial(round: round, rate: rate, driver: driver, kind: .catchUp, fast: UInt64(1500 * w), slow: UInt64(4000 * w), cost: w)
        }
        result.metadata.corpusReducedTo = 341_000
        return result
    }

    /// Trend run: Swift only, one round, one rate.
    static var fixtureTrend: CellResult {
        ReportFixture.result(ReportFixture.cell("append-latency-300-tls", rates: [1000], rounds: 1), drivers: ["swift"]) { round, rate, driver in
            ReportFixture.trial(round: round, rate: rate, driver: driver, fast: 1200, slow: 5000)
        }
    }
}
