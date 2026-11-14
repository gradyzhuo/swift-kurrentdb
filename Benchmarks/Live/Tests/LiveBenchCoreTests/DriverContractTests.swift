import Foundation
import Testing
@testable import LiveBenchCore

@Suite struct DriverContractTests {
    @Test func trialResultJSONFieldNamesAreStable() throws {
        let json = try String(data: JSONEncoder().encode(TrialResult.fixture), encoding: .utf8)!
        for key in [
            "\"client\"", "\"cellId\"", "\"targetRate\"", "\"timing\"", "\"scheduled\"", "\"succeeded\"", "\"failed\"",
            "\"dropped\"", "\"timedOut\"", "\"measuredSeconds\"", "\"cpuUserSeconds\"", "\"cpuSystemSeconds\"",
            "\"maxRssBytes\"", "\"validation\"", "\"expectedEvents\"", "\"receivedEvents\"", "\"payloadSizesOk\"",
        ] {
            #expect(json.contains(key), "missing \(key)")
        }
    }

    @Test func timingRawValuesAreStable() throws {
        #expect(Timing.scheduled.rawValue == "scheduled")
        #expect(Timing.rpcStart.rawValue == "rpcStart")
    }

    @Test func trialResultRoundTrips() throws {
        var r = TrialResult.fixture
        r.ackEnqueued = 10
        r.uniqueDeliveries = 9
        r.redeliveries = 1
        r.catchUpSeconds = 2.5
        r.backlogAtMidpoint = 3
        r.backlogAtEnd = 7
        r.scheduledSecondHalf = 600
        let back = try JSONDecoder().decode(TrialResult.self, from: JSONEncoder().encode(r))
        #expect(back == r)
        #expect(back.backlog == BacklogSamples(atMidpoint: 3, atEnd: 7, scheduledSecondHalf: 600))
    }

    @Test func backlogNeedsAllThreeSamples() throws {
        // A result written before the samples existed (or by ghz) decodes with none of them.
        var r = TrialResult.fixture
        #expect(r.backlog == nil)
        r.backlogAtMidpoint = 3
        r.backlogAtEnd = 7
        #expect(r.backlog == nil)
        let json = try String(data: JSONEncoder().encode(TrialResult.fixture), encoding: .utf8)!
        #expect(!json.contains("backlog"))
    }

    @Test func driverVersionFieldNames() throws {
        let v = DriverVersion(client: "swift", clientVersion: "abc123", runtime: "swift 6.2")
        let json = try String(data: JSONEncoder().encode(v), encoding: .utf8)!
        for key in ["\"client\"", "\"clientVersion\"", "\"runtime\""] { #expect(json.contains(key)) }
    }

    @Test func processUsageIsPositive() {
        let u = ProcessUsage.current()
        #expect(u.maxRss > 1_000_000)
        #expect(u.user >= 0 && u.system >= 0)
    }
}
