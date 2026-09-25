import Foundation
import KurrentDB

// MARK: - Configuration
public struct Config {
    public let steps: [Int]           // VU counts: [10, 50, 100, ...]
    public let writeRate: Int         // ops/s per VU
    public let readRate: Int          // ops/s per VU
    public let warmupDuration: Int    // seconds
    public let stepDuration: Int      // seconds per step
    public let maxInflight: Int       // per VU, per operation
    public let label: String          // version label
    public let outputFile: String     // JSON output path

    public static func fromEnv() -> Config {
        let stepsStr = ProcessInfo.processInfo.environment["STRESS_STEPS"] ?? "10,50,100,250,500,1000"
        let steps = stepsStr.split(separator: ",").compactMap { Int($0) }

        return Config(
            steps: steps,
            writeRate: Int(ProcessInfo.processInfo.environment["STRESS_WRITE_RATE"] ?? "100") ?? 100,
            readRate: Int(ProcessInfo.processInfo.environment["STRESS_READ_RATE"] ?? "100") ?? 100,
            warmupDuration: Int(ProcessInfo.processInfo.environment["STRESS_WARMUP"] ?? "5") ?? 5,
            stepDuration: Int(ProcessInfo.processInfo.environment["STRESS_DURATION"] ?? "30") ?? 30,
            maxInflight: Int(ProcessInfo.processInfo.environment["STRESS_MAX_INFLIGHT"] ?? "200") ?? 200,
            label: ProcessInfo.processInfo.environment["STRESS_LABEL"] ?? "unknown",
            outputFile: ProcessInfo.processInfo.environment["STRESS_OUTPUT"] ?? "stress-result.json"
        )
    }
}

// MARK: - Metrics
public struct OperationMetrics: Codable {
    public let achieved: Double       // ops completed in window / window duration
    public let p50: Double            // ms
    public let p95: Double            // ms
    public let p99: Double            // ms
    public let max: Double            // ms
    public let completed: Int         // successful operations
    public let attempted: Int         // total attempts = completed + errors + shed
    public let errors: Int
    public let shed: Int              // requests not sent (max inflight exceeded)
    public let topErrors: [ErrorCount]

    public init(achieved: Double, p50: Double, p95: Double, p99: Double, max: Double, completed: Int, attempted: Int, errors: Int, shed: Int, topErrors: [ErrorCount]) {
        self.achieved = achieved
        self.p50 = p50
        self.p95 = p95
        self.p99 = p99
        self.max = max
        self.completed = completed
        self.attempted = attempted
        self.errors = errors
        self.shed = shed
        self.topErrors = topErrors
    }
}

public struct ErrorCount: Codable {
    public let type: String
    public let count: Int

    public init(type: String, count: Int) {
        self.type = type
        self.count = count
    }
}

public struct StepResult: Codable {
    public let vus: Int
    public let write: OperationMetrics
    public let read: OperationMetrics
    public let saturated: Bool

    public init(vus: Int, write: OperationMetrics, read: OperationMetrics, saturated: Bool) {
        self.vus = vus
        self.write = write
        self.read = read
        self.saturated = saturated
    }
}

public struct Report: Codable {
    public let label: String
    public let runId: String
    public let steps: [StepResult]

    public init(label: String, runId: String, steps: [StepResult]) {
        self.label = label
        self.runId = runId
        self.steps = steps
    }
}

// MARK: - Histogram-based Percentile Calculation
private struct SimpleHistogram {
    private var buckets: [Int64: Int] = [:]
    private var maxValue: Int64 = 0
    private var count: Int = 0

    mutating func recordValue(_ value: Int64) {
        buckets[value, default: 0] += 1
        count += 1
        maxValue = max(maxValue, value)
    }

    func getValueAtPercentile(_ percentile: Double) -> Int64 {
        guard count > 0 else { return 0 }
        let targetCount = Int(Double(count) * (percentile / 100.0))
        var accumulated = 0

        for value in buckets.keys.sorted() {
            accumulated += buckets[value] ?? 0
            if accumulated >= targetCount {
                return value
            }
        }
        return maxValue
    }

    func getMaxValue() -> Int64 {
        return maxValue
    }
}

// MARK: - Saturation Logic
public func isSaturated(write: OperationMetrics, read: OperationMetrics, vus: Int, targetWriteRate: Int, targetReadRate: Int) -> Bool {
    let writeTarget = Double(vus * targetWriteRate)
    let readTarget = Double(vus * targetReadRate)

    // Throughput check: achieved < 90% of target
    if write.achieved < writeTarget * 0.9 || read.achieved < readTarget * 0.9 {
        return true
    }

    // Latency check: p99 > 1000 ms
    if write.p99 > 1000 || read.p99 > 1000 {
        return true
    }

    // Error rate check: (errors + shed) / attempted > 1%
    if write.attempted > 0 {
        let writeErrorRate = Double(write.errors + write.shed) / Double(write.attempted)
        if writeErrorRate > 0.01 {
            return true
        }
    }

    if read.attempted > 0 {
        let readErrorRate = Double(read.errors + read.shed) / Double(read.attempted)
        if readErrorRate > 0.01 {
            return true
        }
    }

    return false
}

// MARK: - Real Load Generation (Global Open Load Model)
public func runStressTest(client: KurrentDBClient, vus: Int, config: Config, duration: Int) async -> StepResult {
    nonisolated(unsafe) var allMetrics = (writes: [Double](), reads: [Double](), writeErrors: 0, readErrors: 0, writeShed: 0, readShed: 0)
    nonisolated(unsafe) var writeSuccesses = 0, readSuccesses = 0
    let startTime = Date()

    // Global load model parameters
    let globalWriteRate = vus * config.writeRate  // Total write rate across all VUs
    let globalReadRate = vus * config.readRate    // Total read rate across all VUs
    let totalWriteRequests = globalWriteRate * duration
    let totalReadRequests = globalReadRate * duration

    // Spawn VUs
    var vuTasks: [Task<Void, Never>] = []
    for vuID in 0..<vus {
        let task = Task {
            // Write loop: VU k handles requests k, k+vus, k+2*vus, ...
            for globalWriteSeq in stride(from: vuID, to: totalWriteRequests, by: vus) {
                let scheduledTime = startTime.addingTimeInterval(Double(globalWriteSeq) / Double(globalWriteRate))
                let now = Date()
                if now < scheduledTime {
                    try? await Task.sleep(nanoseconds: UInt64((scheduledTime.timeIntervalSince(now)) * 1_000_000_000))
                }

                do {
                    // Measure latency from scheduled time to completion (avoids coordinated omission)
                    let streamName = "stress-\(UUID().uuidString)-\(vuID)"
                    let event = EventData(eventType: "StressEvent", model: ["vu": vuID])
                    _ = try await client.streams(specified: streamName).append(events: [event])
                    let latency = Date().timeIntervalSince(scheduledTime) * 1000 // ms
                    allMetrics.writes.append(latency)
                    writeSuccesses += 1
                } catch {
                    allMetrics.writeErrors += 1
                }
            }

            // Read loop: VU k handles requests k, k+vus, k+2*vus, ...
            for globalReadSeq in stride(from: vuID, to: totalReadRequests, by: vus) {
                let scheduledTime = startTime.addingTimeInterval(Double(globalReadSeq) / Double(globalReadRate))
                let now = Date()
                if now < scheduledTime {
                    try? await Task.sleep(nanoseconds: UInt64((scheduledTime.timeIntervalSince(now)) * 1_000_000_000))
                }

                do {
                    let streamName = "stress-\(UUID().uuidString)-\(vuID)"
                    _ = try await client.streams(specified: streamName).read { $0.limit = 10 }
                    let latency = Date().timeIntervalSince(scheduledTime) * 1000
                    allMetrics.reads.append(latency)
                    readSuccesses += 1
                } catch {
                    allMetrics.readErrors += 1
                }
            }
        }
        vuTasks.append(task)
    }

    // Wait for all VUs to complete
    for task in vuTasks {
        await task.value
    }

    // Compute percentiles using histogram-based calculation
    var writeHistogram = SimpleHistogram()
    var readHistogram = SimpleHistogram()

    // Convert latencies from milliseconds to microseconds and record in histograms
    for writeLatency in allMetrics.writes {
        let micros = Int64(writeLatency * 1000)
        writeHistogram.recordValue(micros)
    }

    for readLatency in allMetrics.reads {
        let micros = Int64(readLatency * 1000)
        readHistogram.recordValue(micros)
    }

    // Extract percentiles and max values, convert back to milliseconds
    let writeP50 = Double(writeHistogram.getValueAtPercentile(50.0)) / 1000.0
    let writeP95 = Double(writeHistogram.getValueAtPercentile(95.0)) / 1000.0
    let writeP99 = Double(writeHistogram.getValueAtPercentile(99.0)) / 1000.0
    let writePMax = Double(writeHistogram.getMaxValue()) / 1000.0

    let readP50 = Double(readHistogram.getValueAtPercentile(50.0)) / 1000.0
    let readP95 = Double(readHistogram.getValueAtPercentile(95.0)) / 1000.0
    let readP99 = Double(readHistogram.getValueAtPercentile(99.0)) / 1000.0
    let readPMax = Double(readHistogram.getMaxValue()) / 1000.0

    // Calculate attempted counts
    let writeAttempted = writeSuccesses + allMetrics.writeErrors + allMetrics.writeShed
    let readAttempted = readSuccesses + allMetrics.readErrors + allMetrics.readShed

    return StepResult(
        vus: vus,
        write: OperationMetrics(
            achieved: Double(writeSuccesses) / Double(duration),
            p50: writeP50, p95: writeP95, p99: writeP99, max: writePMax,
            completed: writeSuccesses,
            attempted: writeAttempted,
            errors: allMetrics.writeErrors,
            shed: allMetrics.writeShed,
            topErrors: []
        ),
        read: OperationMetrics(
            achieved: Double(readSuccesses) / Double(duration),
            p50: readP50, p95: readP95, p99: readP99, max: readPMax,
            completed: readSuccesses,
            attempted: readAttempted,
            errors: allMetrics.readErrors,
            shed: allMetrics.readShed,
            topErrors: []
        ),
        saturated: false  // Will be computed by caller
    )
}
