//
//  DefaultDeadlineLiveTests.swift
//  swift-kurrentdb
//
//  Needs the 3-node cluster from server/docker-compose.yaml. Subscriptions and lazy reads, whose
//  lifetime is the caller's iteration, are not bounded by `defaultDeadline`: under a 1 ms default
//  deadline they must still work. That the deadline does bound completing calls is verified
//  offline in MockClientTests/DefaultDeadlinePathTests, against a listener that never answers.
//

import Foundation
@testable import KurrentDB
import Testing

@Suite("Default deadline (live)", .serialized, .timeLimit(.minutes(2)))
struct DefaultDeadlineLiveTests: Sendable {
    let settings: ClientSettings
    /// Same cluster, 1 ms default deadline.
    let impatient: ClientSettings

    init() {
        settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .certificate(source: .crtInBundle("ca", inBundle: .module)!)
        impatient = settings.defaultDeadline(1)
    }

    private func event() -> EventData {
        EventData(eventType: "DefaultDeadline-Test", model: ["Description": "default deadline"])
    }

    @Test("A subscription outlives the default deadline and still receives events")
    func subscriptionIsNotBounded() async throws {
        let writer = KurrentDBClient(settings: settings)
        defer { try? writer.shutdown() }
        let client = KurrentDBClient(settings: impatient)
        defer { try? client.shutdown() }
        let name = "DefaultDeadline-\(UUID().uuidString)"

        let subscription = try await client.streams(specified: name).subscribe()
        try await Task.sleep(for: .milliseconds(300))   // far beyond the 1 ms deadline
        _ = try await writer.streams(specified: name).append(events: [event()]) { $0.expectedRevision = .any }

        var iterator = subscription.events.makeAsyncIterator()
        let received = try await iterator.next()
        #expect(received?.record.eventType == "DefaultDeadline-Test")
        subscription.cancel()
    }

    @Test("A lazy read is not bounded by the default deadline")
    func lazyReadIsNotBounded() async throws {
        let writer = KurrentDBClient(settings: settings)
        defer { try? writer.shutdown() }
        let client = KurrentDBClient(settings: impatient)
        defer { try? client.shutdown() }
        let name = "DefaultDeadline-\(UUID().uuidString)"
        _ = try await writer.streams(specified: name).append(events: (0 ..< 5).map { _ in event() }) { $0.expectedRevision = .any }

        var count = 0
        for try await _ in client.streams(specified: name).read().lazy { count += 1 }
        #expect(count == 5)
    }
}
