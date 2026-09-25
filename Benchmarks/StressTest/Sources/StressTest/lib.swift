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

// MARK: - Main entry point for running stress test
public func runStressTest(client: KurrentDBClient, vus: Int, config: Config, duration: Int) async -> StepResult {
    // TODO: Implement actual VU spawning, load scheduling, metric collection
    // For now, return stub data
    return StepResult(
        vus: vus,
        write: OperationMetrics(achieved: Double(vus * config.writeRate), p50: 1.5, p95: 3.0, p99: 5.0, max: 10.0, errors: 0, shed: 0, topErrors: []),
        read: OperationMetrics(achieved: Double(vus * config.readRate), p50: 2.0, p95: 4.0, p99: 6.0, max: 12.0, errors: 0, shed: 0, topErrors: []),
        saturated: false
    )
}
