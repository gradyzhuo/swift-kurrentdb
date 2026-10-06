//
//  SubscriptionBackpressureLiveTests.swift
//  swift-kurrentdb
//
//  Needs the 3-node cluster from server/docker-compose.yaml.
//

import Foundation
@testable import KurrentDB
import Testing

@Suite("Subscription backpressure (live)", .serialized, .timeLimit(.minutes(3)))
struct SubscriptionBackpressureLiveTests: Sendable {
    let settings: ClientSettings

    init() {
        settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .certificate(source: .crtInBundle("ca", inBundle: .module)!)
    }

    private func events(_ n: Int) -> [EventData] {
        (0 ..< n).map { _ in EventData(eventType: "Backpressure-Test", model: ["Description": "backpressure"]) }
    }

    private func eventually(timeout: Duration = .seconds(10), _ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    @Test("A slow consumer keeps the client-side buffer bounded")
    func slowConsumerIsBounded() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let stream = client.streams(specified: "Backpressure-\(UUID().uuidString)")
        _ = try await stream.append(events: events(300)) { $0.expectedRevision = .any }

        let subscription = try await stream.subscribe { $0.revision = .start }   // default is .end
        var iterator = subscription.events.makeAsyncIterator()
        _ = try await iterator.next()
        try await Task.sleep(for: .milliseconds(500))

        #expect(subscription.messages.sentCount - subscription.messages.deliveredCount <= subscription.messages.capacity)
        #expect(subscription.messages.sentCount < 100)
        subscription.cancel()
    }

    @Test("cancel() while the consumer waits ends the loop and closes the dedicated connection")
    func cancelWhileWaiting() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let stream = client.streams(specified: "Backpressure-\(UUID().uuidString)")
        _ = try await stream.append(events: events(1)) { $0.expectedRevision = .any }

        let subscription = try await stream.subscribe { $0.revision = .start }
        let consumer = Task {
            var count = 0
            for try await _ in subscription.events { count += 1 }
            return count
        }
        #expect(try await eventually { subscription.messages.deliveredCount >= 2 })   // event + caughtUp consumed
        #expect(client.selector.connections.activeDedicatedConnectionCount == 1)

        subscription.cancel()
        #expect(try await consumer.value == 1)
        #expect(try await eventually { client.selector.connections.activeDedicatedConnectionCount == 0 })
    }

    @Test("$all subscription keeps the buffer bounded too")
    func allStreamsSlowConsumer() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let filler = client.streams(specified: "Backpressure-filler-\(UUID().uuidString)")
        _ = try await filler.append(events: events(300)) { $0.expectedRevision = .any }

        let subscription = try await client.allStreams.subscribe { $0.position = .start }
        var iterator = subscription.events.makeAsyncIterator()
        _ = try await iterator.next()
        try await Task.sleep(for: .milliseconds(500))
        #expect(subscription.messages.sentCount - subscription.messages.deliveredCount <= subscription.messages.capacity)
        #expect(subscription.messages.sentCount < 100)
        subscription.cancel()
    }
}
