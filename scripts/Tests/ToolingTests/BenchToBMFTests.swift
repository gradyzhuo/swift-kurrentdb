import Foundation
import Testing
@testable import Tooling

@Suite struct BenchToBMFTests {
    static func metric(_ unit: String, _ p0: Double, _ p50: Double, _ p90: Double) -> BenchToBMF.Metric {
        BenchToBMF.Metric(scoreUnit: unit, scorePercentiles: ["0.0": p0, "50.0": p50, "90.0": p90, "100.0": p90])
    }

    static func entry(_ name: String, wall: BenchToBMF.Metric? = nil, mallocs: BenchToBMF.Metric? = nil) -> BenchToBMF.Entry {
        var secondary: [String: BenchToBMF.Metric] = [:]
        if let wall { secondary["Time (wall clock)"] = wall }
        if let mallocs { secondary["Malloc (total)"] = mallocs }
        return BenchToBMF.Entry(benchmark: "package.benchmark.OfflineBenchmarks.\(name)", secondaryMetrics: secondary)
    }

    @Test func stripsTheJMHPackagePrefix() {
        #expect(BenchToBMF.benchmarkName("package.benchmark.OfflineBenchmarks.EventData/create-raw-data") == "EventData/create-raw-data")
        #expect(BenchToBMF.benchmarkName("EventData/create-raw-data") == "EventData/create-raw-data")
    }

    @Test func timeUnitsScaleToNanoseconds() throws {
        #expect(try BenchToBMF.nanoseconds(0.584, unit: "μs") == 584.0)
        #expect(try BenchToBMF.nanoseconds(0.584, unit: "µs") == 584.0)  // micro sign variant
        #expect(try BenchToBMF.nanoseconds(0.584, unit: "us") == 584.0)
        #expect(try BenchToBMF.nanoseconds(2.5, unit: "ms") == 2_500_000.0)
        #expect(try BenchToBMF.nanoseconds(1.25, unit: "s") == 1_250_000_000.0)
        #expect(try BenchToBMF.nanoseconds(917, unit: "ns") == 917.0)
        #expect(failure { String(try BenchToBMF.nanoseconds(1, unit: "ks")) } != nil)
    }

    @Test func countUnitsScaleToPlainNumbers() throws {
        #expect(try BenchToBMF.count(1242, unit: "#") == 1242.0)
        #expect(try BenchToBMF.count(3.5, unit: "K") == 3500.0)
        #expect(try BenchToBMF.count(2, unit: "M") == 2_000_000.0)
        #expect(failure { String(try BenchToBMF.count(1, unit: "G")) } != nil)
    }

    @Test func latencyUsesP50WithP0AndP90BoundsInNanoseconds() throws {
        let bmf = try BenchToBMF.convert([Self.entry("StreamIdentifier/create", wall: Self.metric("μs", 0.5, 0.584, 0.666))])
        #expect(bmf["StreamIdentifier/create"]?["latency"] == BenchToBMF.Measure(value: 584.0, lowerValue: 500.0, upperValue: 666.0))
    }

    @Test func allocationsUseP50AndBounds() throws {
        let bmf = try BenchToBMF.convert([
            Self.entry("ClientSettings/parse-single-node", wall: Self.metric("μs", 1, 2, 3), mallocs: Self.metric("#", 1240, 1242, 1243)),
        ])
        #expect(bmf["ClientSettings/parse-single-node"]?["allocations"] == BenchToBMF.Measure(value: 1242.0, lowerValue: 1240.0, upperValue: 1243.0))
    }

    @Test func concurrentBenchmarksReportAllocationsUnderTheirOwnMeasure() throws {
        let bmf = try BenchToBMF.convert([
            Self.entry("Client/append/1x100B", wall: Self.metric("μs", 1, 2, 3), mallocs: Self.metric("#", 117, 121, 127)),
            Self.entry("GRPC/read/1x100B", wall: Self.metric("μs", 1, 2, 3), mallocs: Self.metric("#", 78, 81, 93)),
            Self.entry("ClientSettings/parse-single-node", wall: Self.metric("μs", 1, 2, 3), mallocs: Self.metric("#", 11, 11, 11)),
        ])
        #expect(bmf["Client/append/1x100B"]?.keys.sorted() == ["allocations-concurrent", "latency"])
        #expect(bmf["GRPC/read/1x100B"]?["allocations-concurrent"] == BenchToBMF.Measure(value: 81.0, lowerValue: 78.0, upperValue: 93.0))
        // Only the `Client/` prefix with its slash: `ClientSettings/` keeps the deterministic measure.
        #expect(bmf["ClientSettings/parse-single-node"]?.keys.sorted() == ["allocations", "latency"])
    }

    @Test func benchmarkWithoutWallClockIsSkipped() throws {
        #expect(try BenchToBMF.convert([Self.entry("NoWall", mallocs: Self.metric("#", 0, 0, 0))]).isEmpty)
    }

    @Test func missingMallocsOnlyOmitsThatMeasure() throws {
        let bmf = try BenchToBMF.convert([Self.entry("OnlyWall", wall: Self.metric("ns", 1, 2, 3))])
        #expect(bmf["OnlyWall"]?.keys.sorted() == ["latency"])
    }

    @Test func readsTheFileAndWritesSortedJSON() throws {
        let directory = TemporaryDirectory()
        directory.write("Current_run.jmh.json", """
        [{"benchmark": "package.benchmark.OfflineBenchmarks.Zeta/x", "mode": "thrpt",
          "primaryMetric": {"score": 1.0, "scoreUnit": "# / s", "scorePercentiles": {"50.0": 1.0}},
          "secondaryMetrics": {"Time (wall clock)": {"score": 2, "scoreUnit": "ns", "scorePercentiles": {"0.0": 1, "50.0": 2, "90.0": 3, "100.0": 3}}}},
         {"benchmark": "package.benchmark.OfflineBenchmarks.Alpha/y", "mode": "thrpt",
          "primaryMetric": {"score": 1.0, "scoreUnit": "# / s", "scorePercentiles": {"50.0": 1.0}},
          "secondaryMetrics": {"Time (wall clock)": {"score": 2, "scoreUnit": "μs", "scorePercentiles": {"0.0": 1, "50.0": 2, "90.0": 3, "100.0": 3}}}}]
        """)
        let output = try BenchToBMF.run([directory.url.appendingPathComponent("Current_run.jmh.json").path])
        let bmf = try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: [String: [String: Double]]]
        #expect(bmf == [
            "Alpha/y": ["latency": ["value": 2000, "lower_value": 1000, "upper_value": 3000]],
            "Zeta/x": ["latency": ["value": 2, "lower_value": 1, "upper_value": 3]],
        ])
        #expect(output.range(of: "Alpha/y")!.lowerBound < output.range(of: "Zeta/x")!.lowerBound)
        #expect(!output.contains("\\/"))
    }

    @Test func failsWhenNoBenchmarkConverted() {
        let directory = TemporaryDirectory()
        directory.write("empty.jmh.json", "[]")
        let error = failure { try BenchToBMF.run([directory.url.appendingPathComponent("empty.jmh.json").path]) }
        #expect(error?.status == 1)
        #expect(error?.message.contains("no benchmarks") == true)
        #expect(failure { try BenchToBMF.run([]) }?.status == 2)
    }
}
