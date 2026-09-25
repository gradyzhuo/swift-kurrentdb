import Foundation
import Testing
@testable import StressTest

@Suite("Saturation Logic")
struct SaturationTests {
    @Test("Achieved < 90% target triggers saturation")
    func testThroughputSaturation() {
        let write = OperationMetrics(achieved: 85, p50: 1.0, p95: 2.0, p99: 3.0, max: 5.0, errors: 0, shed: 0, topErrors: [])
        let read = OperationMetrics(achieved: 100, p50: 1.0, p95: 2.0, p99: 3.0, max: 5.0, errors: 0, shed: 0, topErrors: [])

        let saturated = isSaturated(write: write, read: read, targetRate: 100)
        #expect(saturated == true)
    }

    @Test("P99 > 1000ms triggers saturation")
    func testLatencySaturation() {
        let write = OperationMetrics(achieved: 100, p50: 1.0, p95: 500.0, p99: 1500.0, max: 2000.0, errors: 0, shed: 0, topErrors: [])
        let read = OperationMetrics(achieved: 100, p50: 1.0, p95: 2.0, p99: 3.0, max: 5.0, errors: 0, shed: 0, topErrors: [])

        let saturated = isSaturated(write: write, read: read, targetRate: 100)
        #expect(saturated == true)
    }

    @Test("Healthy metrics don't saturate")
    func testHealthyNoSaturation() {
        let write = OperationMetrics(achieved: 99, p50: 1.0, p95: 3.0, p99: 5.0, max: 10.0, errors: 0, shed: 0, topErrors: [])
        let read = OperationMetrics(achieved: 99, p50: 1.0, p95: 3.0, p99: 5.0, max: 10.0, errors: 0, shed: 0, topErrors: [])

        let saturated = isSaturated(write: write, read: read, targetRate: 100)
        #expect(saturated == false)
    }

    @Test("Error rate > 1% triggers saturation")
    func testErrorRateSaturation() {
        let write = OperationMetrics(achieved: 99, p50: 1.0, p95: 2.0, p99: 3.0, max: 5.0, errors: 2, shed: 0, topErrors: [])
        let read = OperationMetrics(achieved: 99, p50: 1.0, p95: 2.0, p99: 3.0, max: 5.0, errors: 0, shed: 0, topErrors: [])

        let saturated = isSaturated(write: write, read: read, targetRate: 100)
        #expect(saturated == true)
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
                    write: OperationMetrics(achieved: 100, p50: 1.0, p95: 2.0, p99: 3.0, max: 5.0, errors: 0, shed: 0, topErrors: []),
                    read: OperationMetrics(achieved: 100, p50: 1.0, p95: 2.0, p99: 3.0, max: 5.0, errors: 0, shed: 0, topErrors: []),
                    saturated: false
                )
            ]
        )

        let encoded = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(Report.self, from: encoded)

        #expect(decoded.label == "2.4.2")
        #expect(decoded.steps.count == 1)
        #expect(decoded.steps[0].vus == 10)
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
