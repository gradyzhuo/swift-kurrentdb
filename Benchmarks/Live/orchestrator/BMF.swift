import Foundation
import LiveBenchCore

/// Bencher Metric Format for the nightly Swift-only trend: `{"<benchmark>": {"<measure>": {"value": …, "upper_value": …}}}`.
///
/// One benchmark per (cell, rate), named `live/<cellId>@<rate>` so the history stays attached to it. Measures use
/// Bencher's built-in units, as the offline suite does (`scripts/bench_to_bmf.py`):
/// - `latency`: nanoseconds; `value` is p50, `upper_value` p99 (left out when p99 is censored, "> deadline");
/// - `throughput`: successful operations per second of the measure window.
/// A trial with an error, without a single success, or that did not sustain its rate gives no benchmark (its latency
/// would be a censored lower bound, not a point to trend), and `log` says why. ghz/.NET trials are ignored.
enum BMF {
    /// The fixed moderate rate a trend run uses: the lower middle of the cell's rate ramp.
    static func trendRate(for cell: Cell) -> Double {
        let rates = cell.rates.sorted()
        return rates.isEmpty ? 0 : rates[(rates.count - 1) / 2]
    }

    static func benchmarkName(cellId: String, rate: Double) -> String {
        "live/\(cellId)@\(TrialRunner.rateLabel(rate))"
    }

    static func trend(_ result: CellResult, log: (String) -> Void = BMF.standardError) -> Data { trend([result], log: log) }

    static func trend(_ results: [CellResult], log: (String) -> Void = BMF.standardError) -> Data {
        var benchmarks: [String: [String: [String: Double]]] = [:]
        for result in results {
            let swift = result.trials
                .filter { $0.driver == CellAnalysis.swift }
                .sorted { $0.round < $1.round }
                .map { TrialFigures($0, cell: result.cell) }
            for figures in swift {
                let name = benchmarkName(cellId: result.cell.id, rate: figures.trial.rate)
                guard benchmarks[name] == nil else { continue }
                guard figures.valid else {
                    log("\(name): skipped, the trial failed: \(figures.trial.error ?? "no result")")
                    continue
                }
                guard let succeeded = figures.trial.result?.succeeded, succeeded > 0 else {
                    log("\(name): skipped, no operation succeeded")
                    continue
                }
                guard figures.sustained else {
                    log("\(name): skipped, the rate was not sustained (its latency is censored)")
                    continue
                }
                var measures: [String: [String: Double]] = [:]
                if let p50 = figures.p50.micros {
                    var latency = ["value": p50 * 1000]
                    if let p99 = figures.p99.micros { latency["upper_value"] = p99 * 1000 }
                    measures["latency"] = latency
                }
                if let rate = figures.achievedRate, rate.isFinite {
                    measures["throughput"] = ["value": rate]
                }
                if !measures.isEmpty { benchmarks[name] = measures }
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Only finite doubles reach the dictionary, so encoding cannot fail.
        return (try? encoder.encode(benchmarks)) ?? Data("{}".utf8)
    }

    static func standardError(_ line: String) {
        FileHandle.standardError.write(Data("[trend] \(line)\n".utf8))
    }
}
