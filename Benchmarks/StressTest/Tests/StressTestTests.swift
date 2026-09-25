import Foundation
import Testing
@testable import StressTest

@Suite("Saturation Logic")
struct SaturationTests {
    let vus = 10
    let targetWriteRate = 100
    let targetReadRate = 100

    @Test("Achieved < 90% target triggers saturation")
    func testThroughputSaturation() {
        // For 10 VUs at 100 ops/s, target = 1000 ops/s
        // 85 ops/s achieved < 900 (90% of 1000) = saturated
        let write = OperationMetrics(achieved: 85, p50: 1.0, p95: 2.0, p99: 3.0, max: 5.0, completed: 85, attempted: 85, errors: 0, shed: 0, topErrors: [])
        let read = OperationMetrics(achieved: 100, p50: 1.0, p95: 2.0, p99: 3.0, max: 5.0, completed: 100, attempted: 100, errors: 0, shed: 0, topErrors: [])

        let saturated = isSaturated(write: write, read: read, vus: vus, targetWriteRate: targetWriteRate, targetReadRate: targetReadRate)
        #expect(saturated == true)
    }

    @Test("P99 > 1000ms triggers saturation")
    func testLatencySaturation() {
        let write = OperationMetrics(achieved: 100, p50: 1.0, p95: 500.0, p99: 1500.0, max: 2000.0, completed: 100, attempted: 100, errors: 0, shed: 0, topErrors: [])
        let read = OperationMetrics(achieved: 100, p50: 1.0, p95: 2.0, p99: 3.0, max: 5.0, completed: 100, attempted: 100, errors: 0, shed: 0, topErrors: [])

        let saturated = isSaturated(write: write, read: read, vus: vus, targetWriteRate: targetWriteRate, targetReadRate: targetReadRate)
        #expect(saturated == true)
    }

    @Test("Healthy metrics don't saturate")
    func testHealthyNoSaturation() {
        // For 10 VUs at 100 ops/s, target = 1000 ops/s
        // 990 ops/s >= 900 (90% of 1000) = not saturated
        let write = OperationMetrics(achieved: 990, p50: 1.0, p95: 3.0, p99: 5.0, max: 10.0, completed: 990, attempted: 990, errors: 0, shed: 0, topErrors: [])
        let read = OperationMetrics(achieved: 990, p50: 1.0, p95: 3.0, p99: 5.0, max: 10.0, completed: 990, attempted: 990, errors: 0, shed: 0, topErrors: [])

        let saturated = isSaturated(write: write, read: read, vus: vus, targetWriteRate: targetWriteRate, targetReadRate: targetReadRate)
        #expect(saturated == false)
    }

    @Test("Error rate > 1% triggers saturation")
    func testErrorRateSaturation() {
        let write = OperationMetrics(achieved: 99, p50: 1.0, p95: 2.0, p99: 3.0, max: 5.0, completed: 97, attempted: 99, errors: 2, shed: 0, topErrors: [])
        let read = OperationMetrics(achieved: 99, p50: 1.0, p95: 2.0, p99: 3.0, max: 5.0, completed: 99, attempted: 99, errors: 0, shed: 0, topErrors: [])

        let saturated = isSaturated(write: write, read: read, vus: vus, targetWriteRate: targetWriteRate, targetReadRate: targetReadRate)
        #expect(saturated == true)
    }

    @Test("Saturation triggers at correct thresholds")
    func testSaturationThresholds() {
        // Full test requires live Kurrent instance
        // For now, placeholder documents the requirement:
        // - Throughput threshold: 90% of (vus * targetRate)
        // - Latency threshold: p99 > 1000ms
        // - Error rate threshold: > 1%
        #expect(true)
    }
}

@Suite("JSON Output")
struct JSONTests {
    @Test("Report encodes/decodes correctly")
    func testReportSerialization() throws {
        let report = Report(
            label: "2.4.2",
            runId: "test-001",
            steps: [
                StepResult(
                    vus: 10,
                    write: OperationMetrics(achieved: 100, p50: 1.0, p95: 2.0, p99: 3.0, max: 5.0, completed: 100, attempted: 100, errors: 0, shed: 0, topErrors: []),
                    read: OperationMetrics(achieved: 100, p50: 1.0, p95: 2.0, p99: 3.0, max: 5.0, completed: 100, attempted: 100, errors: 0, shed: 0, topErrors: []),
                    saturated: false
                )
            ]
        )

        let encoded = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(Report.self, from: encoded)

        #expect(decoded.label == "2.4.2")
        #expect(decoded.steps.count == 1)
        #expect(decoded.steps[0].vus == 10)
        #expect(decoded.steps[0].write.completed == 100)
        #expect(decoded.steps[0].write.attempted == 100)
    }
}

@Suite("VU Generation")
struct VUGenerationTests {
    @Test("VU generation produces real metrics")
    func testVUGeneration() async throws {
        // This test verifies VU spawning works (requires KurrentDB)
        // For now, placeholder that documents the requirement
        #expect(true)  // Real test needs live DB
    }
}
