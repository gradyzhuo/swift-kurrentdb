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
    public let errors: Int
    public let shed: Int              // requests not sent (max inflight exceeded)
    public let topErrors: [ErrorCount]

    public init(achieved: Double, p50: Double, p95: Double, p99: Double, max: Double, errors: Int, shed: Int, topErrors: [ErrorCount]) {
        self.achieved = achieved
        self.p50 = p50
        self.p95 = p95
        self.p99 = p99
        self.max = max
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

// MARK: - Saturation Logic
public func isSaturated(write: OperationMetrics, read: OperationMetrics, targetRate: Int) -> Bool {
    // achieved < 90% of target
    let writeAchieved = write.achieved
    let readAchieved = read.achieved
    if writeAchieved < Double(targetRate) * 0.9 || readAchieved < Double(targetRate) * 0.9 {
        return true
    }

    // p99 > 1000 ms
    if write.p99 > 1000 || read.p99 > 1000 {
        return true
    }

    // error% or shed% > 1%
    let totalWriteAttempts = write.errors + write.shed + Int(writeAchieved) // approximate
    let totalReadAttempts = read.errors + read.shed + Int(readAchieved)

    if totalWriteAttempts > 0 && Double(write.errors + write.shed) / Double(totalWriteAttempts) > 0.01 {
        return true
    }
    if totalReadAttempts > 0 && Double(read.errors + read.shed) / Double(totalReadAttempts) > 0.01 {
        return true
    }

    return false
}

// MARK: - Helper function for percentile calculation
private func calculatePercentile(_ sorted: [Double], percentile: Double) -> Double {
    guard !sorted.isEmpty else { return 0 }
    let index = Int(Double(sorted.count) * percentile)
    let clampedIndex = max(0, min(index, sorted.count - 1))
    return sorted[clampedIndex]
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

    // Compute percentiles from sorted arrays
    let writeSorted = allMetrics.writes.sorted()
    let readSorted = allMetrics.reads.sorted()

    let writeP50 = calculatePercentile(writeSorted, percentile: 0.50)
    let writeP95 = calculatePercentile(writeSorted, percentile: 0.95)
    let writeP99 = calculatePercentile(writeSorted, percentile: 0.99)
    let writePMax = writeSorted.max() ?? 0

    let readP50 = calculatePercentile(readSorted, percentile: 0.50)
    let readP95 = calculatePercentile(readSorted, percentile: 0.95)
    let readP99 = calculatePercentile(readSorted, percentile: 0.99)
    let readPMax = readSorted.max() ?? 0

    return StepResult(
        vus: vus,
        write: OperationMetrics(
            achieved: Double(writeSuccesses) / Double(duration),
            p50: writeP50, p95: writeP95, p99: writeP99, max: writePMax,
            errors: allMetrics.writeErrors,
            shed: allMetrics.writeShed,
            topErrors: []
        ),
        read: OperationMetrics(
            achieved: Double(readSuccesses) / Double(duration),
            p50: readP50, p95: readP95, p99: readP99, max: readPMax,
            errors: allMetrics.readErrors,
            shed: allMetrics.readShed,
            topErrors: []
        ),
        saturated: false  // Will be computed by caller
    )
}
