import Foundation

/// Convert package-benchmark JMH output into Bencher Metric Format (BMF).
///
/// `swift package benchmark --format jmh` writes one JSON array with an entry per
/// benchmark. The primary metric is throughput; wall clock and allocation counts
/// live in `secondaryMetrics`, with units that package-benchmark scales per
/// benchmark (ns / μs / ms, # / K / M). This normalises them:
///
///     latency      p50 wall clock in nanoseconds, bounds = p0 and p90
///     allocations  p50 `Malloc (total)`, bounds = p0 and p90
///
/// Benchmarks without a wall clock metric are skipped; the conversion fails if no
/// benchmark was converted so a broken run cannot upload an empty report.
public enum BenchToBMF {
    public static let usage = "usage: bench-to-bmf <Current_run.jmh.json> > bmf.json"

    static let jmhPrefix = "package.benchmark."
    static let wallClock = "Time (wall clock)"
    static let mallocTotal = "Malloc (total)"
    static let timeScale: [String: Double] = ["ns": 1, "μs": 1e3, "µs": 1e3, "us": 1e3, "ms": 1e6, "s": 1e9]
    static let countScale: [String: Double] = ["#": 1, "K": 1e3, "M": 1e6]

    public struct Metric: Decodable, Equatable, Sendable {
        public var scoreUnit: String
        public var scorePercentiles: [String: Double]

        public init(scoreUnit: String, scorePercentiles: [String: Double]) {
            self.scoreUnit = scoreUnit
            self.scorePercentiles = scorePercentiles
        }
    }

    public struct Entry: Decodable, Equatable, Sendable {
        public var benchmark: String
        public var secondaryMetrics: [String: Metric]?

        public init(benchmark: String, secondaryMetrics: [String: Metric]? = nil) {
            self.benchmark = benchmark
            self.secondaryMetrics = secondaryMetrics
        }
    }

    public struct Measure: Encodable, Equatable, Sendable {
        public var value: Double
        public var lowerValue: Double
        public var upperValue: Double

        public init(value: Double, lowerValue: Double, upperValue: Double) {
            self.value = value
            self.lowerValue = lowerValue
            self.upperValue = upperValue
        }

        enum CodingKeys: String, CodingKey {
            case value
            case lowerValue = "lower_value"
            case upperValue = "upper_value"
        }
    }

    /// Strips the `package.benchmark.<target>.` prefix JMH output adds.
    public static func benchmarkName(_ jmhName: String) -> String {
        guard jmhName.hasPrefix(jmhPrefix) else { return jmhName }
        let rest = jmhName.dropFirst(jmhPrefix.count)
        guard let dot = rest.firstIndex(of: ".") else { return String(rest) }
        return String(rest[rest.index(after: dot)...])
    }

    public static func nanoseconds(_ value: Double, unit: String) throws(ToolError) -> Double {
        guard let scale = timeScale[unit] else { throw ToolError(message: "unknown time unit '\(unit)'") }
        return value * scale
    }

    public static func count(_ value: Double, unit: String) throws(ToolError) -> Double {
        guard let scale = countScale[unit] else { throw ToolError(message: "unknown count unit '\(unit)'") }
        return value * scale
    }

    /// BMF: benchmark name → measure name → value with p0/p90 bounds.
    public static func convert(_ entries: [Entry]) throws(ToolError) -> [String: [String: Measure]] {
        var bmf: [String: [String: Measure]] = [:]
        for entry in entries {
            let secondary = entry.secondaryMetrics ?? [:]
            guard let wall = secondary[wallClock] else { continue }
            var measures = ["latency": try measure(wall, scale: nanoseconds)]
            if let mallocs = secondary[mallocTotal] {
                measures["allocations"] = try measure(mallocs, scale: count)
            }
            bmf[benchmarkName(entry.benchmark)] = measures
        }
        return bmf
    }

    private static func measure(_ metric: Metric, scale: (Double, String) throws(ToolError) -> Double) throws(ToolError) -> Measure {
        func percentile(_ key: String) throws(ToolError) -> Double {
            guard let value = metric.scorePercentiles[key] else { throw ToolError(message: "metric lacks percentile \(key)") }
            return try scale(value, metric.scoreUnit)
        }
        return Measure(value: try percentile("50.0"), lowerValue: try percentile("0.0"), upperValue: try percentile("90.0"))
    }

    public static func run(_ arguments: [String]) throws(ToolError) -> String {
        let arguments = try Arguments(arguments, usage: usage)
        let path = try arguments.positional(count: 1)[0]
        let entries: [Entry]
        do {
            entries = try JSONDecoder().decode([Entry].self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        } catch {
            throw ToolError(message: "error: cannot read \(path): \(error)")
        }
        let bmf = try convert(entries)
        guard !bmf.isEmpty else {
            throw ToolError(message: "error: no benchmarks with a wall clock metric in \(path)")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            return String(decoding: try encoder.encode(bmf), as: UTF8.self)
        } catch {
            throw ToolError(message: "error: cannot encode BMF: \(error)")
        }
    }
}
