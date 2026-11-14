import Foundation
import Histogram

/// JSON latency histogram exchanged between drivers and the orchestrator: `[valueMicros, count]` buckets.
public struct HistogramFile: Codable, Equatable, Sendable {
    public var unit: String = "us"
    public var buckets: [[UInt64]]

    public init(unit: String = "us", buckets: [[UInt64]]) {
        self.unit = unit
        self.buckets = buckets
    }

    public init(_ histogram: Histogram<UInt64>) {
        var buckets: [[UInt64]] = []
        for v in histogram.recordedValues() {
            buckets.append([histogram.lowestEquivalentForValue(v.value), UInt64(v.count)])
        }
        self.init(buckets: buckets)
    }

    public func histogram() -> Histogram<UInt64> {
        var h = Histogram<UInt64>(lowestDiscernibleValue: 1, highestTrackableValue: 60_000_000, numberOfSignificantValueDigits: .three)
        for b in buckets where b.count == 2 {
            _ = h.record(min(max(b[0], 1), 60_000_000), count: b[1])
        }
        return h
    }
}
