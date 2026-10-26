import Foundation
@testable import LiveBenchCore
@testable import LiveOrchestrator
import Testing

@Suite("Report")
struct ReportTests {
    static let allFixtures: [CellResult] = [
        .fixtureWithLosses, .fixtureAllFailed, .fixtureSystemLimited, .fixtureHeadroomUnavailable,
        .fixtureWithGhz, .fixtureAborted, .fixturePersistent, .fixtureCatchUpReduced, .fixtureTrend,
    ]

    /// The body rows (`<tr data-rate=…>`) of every comparison table (`<table class="ratios">`).
    private func ratioRows(_ html: String) -> [String] {
        let tables = html.components(separatedBy: "<table class=\"ratios\">").dropFirst()
        return tables.flatMap { table -> [String] in
            Array(table.components(separatedBy: "</table>")[0].components(separatedBy: "<tr").dropFirst())
        }.filter { $0.contains("data-rate=") }
    }

    private func comparison(_ result: CellResult, rate: Double) -> StepComparison? {
        CellAnalysis(result).steps.first { $0.rate == rate }?.comparison
    }

    @Test func censoredPercentileRendersAsDeadline() {
        #expect(Report.render([.fixtureWithLosses]).contains("&gt; deadline"))
    }

    @Test func systemLimitedStepGetsNoVerdict() throws {
        let limited = try #require(comparison(.fixtureSystemLimited, rate: 500))
        #expect(limited.headroom == .systemLimited)
        #expect(limited.ratios.isEmpty)
        #expect(limited.noRatioReason == "system-limited: server headroom gate failed; no SDK comparison")
        let roomy = try #require(comparison(.fixtureSystemLimited, rate: 250))
        #expect(!roomy.ratios.isEmpty)

        let rows = ratioRows(Report.render([.fixtureSystemLimited]))
        let top = rows.filter { $0.contains("data-rate=\"500\"") }
        #expect(top.count == 1)
        for row in top {
            #expect(row.contains("system-limited"))
            #expect(!row.contains("×"))
            for verdict in ["meets", "misses", "inconclusive", "insufficient rounds"] { #expect(!row.contains(verdict)) }
        }
        #expect(rows.contains { $0.contains("data-rate=\"250\"") && $0.contains("meets") })
    }

    @Test func headroomUnavailableStepGetsNoVerdict() throws {
        for rate in [250.0, 500] {
            let step = try #require(comparison(.fixtureHeadroomUnavailable, rate: rate))
            #expect(step.headroom == .unavailable)
            #expect(step.ratios.isEmpty)
            #expect(step.noRatioReason == "headroom unavailable: server headroom not measured; no SDK comparison")
        }
        let rows = ratioRows(Report.render([.fixtureHeadroomUnavailable]))
        #expect(rows.count == 2)
        for row in rows {
            #expect(row.contains("headroom unavailable"))
            #expect(!row.contains("×"))
            for verdict in ["meets", "misses", "inconclusive", "insufficient rounds"] { #expect(!row.contains(verdict)) }
        }
    }

    @Test func ceilingNeedsHeadroomInEveryPairedTrial() throws {
        // Swift sustains 250 only, .NET also 500: a ceiling ratio with roomy headroom everywhere.
        #expect(CellAnalysis(.fixtureWithLosses).ceiling?.estimate != nil)
        for headroom in [ReportFixture.saturated, nil] {
            var result = CellResult.fixtureWithLosses
            let index = try #require(result.trials.firstIndex { $0.driver == "dotnet" && $0.rate == 500 })
            result.trials[index].headroom = headroom
            let analysis = CellAnalysis(result)
            #expect(analysis.ceiling == nil)
            #expect(analysis.ceilingNote?.contains(headroom == nil ? "headroom unavailable" : "system-limited") == true)
            #expect(!ratioRows(Report.render([result])).contains { $0.contains("data-rate=\"ceiling\"") })
        }
    }

    @Test func unsustainedUpperPercentilesAreMarkedCensored() throws {
        // Swift loses 0.5% at 500/s: not sustained, yet its p99 is a number. It is shown as a lower bound.
        var result = CellResult.fixtureWithLosses
        for index in result.trials.indices where result.trials[index].driver == "swift" && result.trials[index].rate == 500 {
            result.trials[index] = ReportFixture.trial(round: result.trials[index].round, rate: 500, driver: "swift", fast: 1100, slow: 4000, lost: 150)
        }
        let html = Report.render([result])
        #expect(html.contains("≥ 4.0 ms"))
        #expect(html.contains("circle class=\"swift hollow\""))
        // Sustained steps keep plain numbers.
        #expect(!html.contains("≥ 3.0 ms"))
    }

    @Test func unsustainedStepHasNoRatios() throws {
        let step = try #require(comparison(.fixtureWithLosses, rate: 500))
        #expect(step.ratios.isEmpty)
        #expect(step.noRatioReason?.contains("Swift") == true)
        // The sustained step pairs all five rounds: p50 within the target, p99 above it.
        let low = try #require(comparison(.fixtureWithLosses, rate: 250))
        #expect(low.ratios.first { $0.metric == .p50 }?.verdict == .meets)
        #expect(low.ratios.first { $0.metric == .p99 }?.verdict == .misses)
        #expect(low.ratios.first { $0.metric == .p99 }?.estimate?.rounds == 5)
    }

    @Test func ghzLatencyNeverInARatio() {
        let withGhz = Report.render([.fixtureWithGhz])
        var withoutGhz = CellResult.fixtureWithGhz
        withoutGhz.trials.removeAll { $0.driver == "ghz" }
        // ghz changes nothing in any comparison, and no ratio row names it.
        #expect(ratioRows(withGhz) == ratioRows(Report.render([withoutGhz])))
        #expect(!ratioRows(withGhz).isEmpty)
        #expect(ratioRows(withGhz).allSatisfy { !$0.lowercased().contains("ghz") })
        #expect(withGhz.contains("transport reference"))
        #expect(withGhz.contains("RPC start"))
    }

    @Test func roundWithOneClientMissingIsNotPaired() throws {
        // .NET's round-4 trial at 250/s failed: four rounds pair, fewer than a headline cell's five.
        let step = try #require(comparison(.fixturePersistent, rate: 250))
        let p50 = try #require(step.ratios.first { $0.metric == .p50 })
        #expect(p50.estimate?.rounds == 4)
        #expect(p50.verdict == .insufficientRounds)
    }

    @Test func persistentSubscriptionShowsFairnessNotesAndShortfall() {
        let html = Report.render([.fixturePersistent])
        #expect(html.contains("bufferSize"))
        #expect(html.contains("second gRPC channel"))
        #expect(html.contains("thread pool"))
        #expect(html.contains("acknowledged progress"))
        // .NET at 4000/s: 240,000 written, 239,970 delivered, 238,800 acknowledged in each round.
        #expect(html.contains("239,970"))
        #expect(html.contains("238,800"))
        #expect(!html.contains("Swift ÷ .NET acknowledged"))
    }

    @Test func reportHasNoNaN() {
        #expect(!Report.render([.fixtureAllFailed]).contains("NaN"))
        let html = Report.render(Self.allFixtures)
        #expect(html.range(of: #"\b(NaN|nan|inf|Infinity)\b"#, options: .regularExpression) == nil)
    }

    @Test func abortedCellShowsReasonAndNoRatios() throws {
        let analysis = CellAnalysis(.fixtureAborted)
        #expect(analysis.steps.allSatisfy { $0.comparison?.ratios.isEmpty ?? true })
        let html = Report.render([.fixtureAborted])
        #expect(html.contains("400 MB are"))
        #expect(ratioRows(html).isEmpty)
    }

    @Test func corpusReductionAndDisclaimersAreStated() {
        let html = Report.render([.fixtureCatchUpReduced])
        #expect(html.contains("341,000"))
        #expect(html.contains("loopback"))
        #expect(html.contains("no-op"))
    }

    @Test func errorsAreEscapedAndRedacted() {
        var result = CellResult.fixturePersistent
        result.trials[0].notes = ["<script>alert(1)</script>"]
        let html = Report.render([result])
        #expect(!html.contains("<script>alert"))
        #expect(html.contains("&lt;script&gt;"))
        for leak in ["/Users/alice", "/home/bob", "10.1.2.3"] { #expect(!html.contains(leak)) }
        #expect(html.contains("~/tmp/live/x.json"))
    }

    @Test func pageIsSelfContainedWithBothThemes() {
        let html = Report.render(Self.allFixtures)
        #expect(html.hasPrefix("<!doctype html>"))
        #expect(html.contains("prefers-color-scheme: dark"))
        #expect(html.contains("<svg"))
        #expect(!html.contains("<script"))
        #expect(!html.contains("http://") && !html.contains("src=\"http"))
        #expect(html.contains("name=\"viewport\""))
    }
}

@Suite("Bencher output")
struct BMFTests {
    @Test func trendHasLatencyAndThroughput() throws {
        let json = try #require(JSONSerialization.jsonObject(with: BMF.trend([.fixtureTrend])) as? [String: [String: [String: Double]]])
        let bench = try #require(json["live/append-latency-300-tls@1000"])
        // Latency in nanoseconds (Bencher's `latency` measure): p50 is the fast bucket, p99 the slow one.
        let latency = try #require(bench["latency"])
        #expect(latency["value"] == 1_200_000)
        #expect(latency["upper_value"] == 5_000_000)
        #expect(bench["throughput"]?["value"] == 1000)
    }

    @Test func failedOrUnsustainedTrialsLeaveGaps() throws {
        var lines: [String] = []
        let failed = try #require(JSONSerialization.jsonObject(with: BMF.trend([.fixtureAllFailed], log: { lines.append($0) })) as? [String: Any])
        #expect(failed.isEmpty)
        #expect(lines.contains { $0.contains("no operation succeeded") })

        // Swift lost 2% at 500/s: not sustained, so no trend point (its latency is a censored lower bound).
        var lossy = CellResult.fixtureWithLosses
        lossy.trials.removeAll { $0.driver != "swift" || $0.round != 0 }
        lines = []
        let json = try #require(JSONSerialization.jsonObject(with: BMF.trend([lossy], log: { lines.append($0) })) as? [String: [String: [String: Double]]])
        #expect(json["live/append-latency-losses@500"] == nil)
        #expect(json["live/append-latency-losses@250"]?["latency"]?["upper_value"] != nil)
        #expect(lines == ["live/append-latency-losses@500: skipped, the rate was not sustained (its latency is censored)"])
    }

    @Test func trendRateIsTheLowerMiddleStep() {
        #expect(BMF.trendRate(for: ReportFixture.cell("a", rates: [250, 500, 1000, 2000, 4000, 8000], rounds: 5)) == 1000)
        #expect(BMF.trendRate(for: ReportFixture.cell("b", rates: [250, 1000, 4000], rounds: 5)) == 1000)
        #expect(BMF.trendRate(for: ReportFixture.cell("c", rates: [250, 1000], rounds: 5)) == 250)
    }
}
