import Foundation
@testable import LiveBenchCore
import Testing

@Suite("Harness floor")
struct HarnessFloorTests {
    @Test func noOpFloorAccountsEveryOperationAndReportsProcessFigures() async {
        let floor = await measureHarnessFloor(rate: 1000, seconds: 0.2, warmupSeconds: 0.1)
        #expect(floor.rate == 1000 && floor.seconds == 0.2)
        #expect(floor.scheduled == 200 && floor.succeeded == 200)
        #expect(floor.p50Micros <= floor.p99Micros && floor.p99Micros <= floor.p999Micros && floor.p999Micros <= floor.maxMicros)
        #expect(floor.cpuSeconds >= 0 && floor.cpuSeconds.isFinite)
        #expect(floor.maxRssBytes > 0)
        #expect(!floor.runtime.isEmpty)
    }

    /// The .NET driver's `floor` prints the same object (`OpenLoopParityTests.dotnetFloorPrintsTheSharedFields`).
    @Test func jsonFieldsAreTheContractsFloorFields() throws {
        let floor = HarnessFloor(
            rate: 1000, seconds: 5, scheduled: 5000, succeeded: 5000, p50Micros: 7, p99Micros: 200, p999Micros: 400,
            maxMicros: 900, cpuSeconds: 0.1, maxRssBytes: 10_000_000, runtime: "swift 6.2"
        )
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(floor)) as? [String: Any])
        #expect(Set(object.keys) == HarnessFloor.fieldNames)
    }
}
