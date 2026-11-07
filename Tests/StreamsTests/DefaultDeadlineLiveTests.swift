//
//  DefaultDeadlineLiveTests.swift
//  swift-kurrentdb
//
//  Needs the 3-node cluster from server/docker-compose.yaml. A subscription, whose lifetime is the
//  caller's iteration, is not bounded by `defaultDeadline`: under a 1 ms default deadline it must
//  still work. A lazy read is bounded only while it is established (node selection to the server's
//  first response, one budget); its iteration outlives the deadline. That the deadline bounds
//  completing calls, and every way establishing a lazy read can expire, is verified offline in
//  MockClientTests/DefaultDeadlinePathTests.
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
        defer { writer.shutdown() }
        let client = KurrentDBClient(settings: impatient)
        defer { client.shutdown() }
        let name = "DefaultDeadline-\(UUID().uuidString)"

        let subscription = try await client.streams(specified: name).subscribe()
        try await Task.sleep(for: .milliseconds(300))   // far beyond the 1 ms deadline
        _ = try await writer.streams(specified: name).append(events: [event()]) { $0.expectedRevision = .any }

        var iterator = subscription.events.makeAsyncIterator()
        let received = try await iterator.next()
        #expect(received?.record.eventType == "DefaultDeadline-Test")
        subscription.cancel()
    }

    @Test("Establishing a lazy read is bounded by the default deadline")
    func lazyReadEstablishmentIsBounded() async throws {
        let writer = KurrentDBClient(settings: settings)
        defer { writer.shutdown() }
        let client = KurrentDBClient(settings: impatient)
        defer { client.shutdown() }
        let name = "DefaultDeadline-\(UUID().uuidString)"
        _ = try await writer.streams(specified: name).append(events: (0 ..< 5).map { _ in event() }) { $0.expectedRevision = .any }

        // Node selection alone takes longer than 1 ms: the first next() ends with the budget.
        let iterator = client.streams(specified: name).read().makeAsyncIterator()
        await #expect(throws: KurrentError.deadlineExceeded) { _ = try await iterator.next() }
    }

    @Test("A lazy read's iteration outlives the default deadline")
    func lazyReadIterationOutlivesTheDeadline() async throws {
        let writer = KurrentDBClient(settings: settings)
        defer { writer.shutdown() }
        let client = KurrentDBClient(settings: settings.defaultDeadline(500))
        defer { client.shutdown() }
        let name = "DefaultDeadline-\(UUID().uuidString)"
        _ = try await writer.streams(specified: name).append(events: (0 ..< 30).map { _ in event() }) { $0.expectedRevision = .any }
        // Discovered beforehand, so the 500 ms budget covers the read's own establishment only.
        _ = try await client.selector.select()

        // 30 events at 50 ms each: about three times the deadline.
        var count = 0
        for try await _ in client.streams(specified: name).read() {
            count += 1
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(count == 30)
    }
}
