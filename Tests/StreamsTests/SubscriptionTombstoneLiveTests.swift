//
//  SubscriptionTombstoneLiveTests.swift
//  swift-kurrentdb
//
//  A catch-up subscription on a stream that gets tombstoned ends with
//  KurrentError.resourceDeleted, like a read of a tombstoned stream.
//

import Foundation
@testable import KurrentDB
import Testing

@Suite("Subscription on a tombstoned stream", .serialized)
struct SubscriptionTombstoneLiveTests: Sendable {
    let settings: ClientSettings

    init() {
        settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .certificate(source: .crtInBundle("ca", inBundle: .module)!)
    }

    @Test("Tombstoning the stream while subscribed ends events with resourceDeleted, after the events before it")
    func testTombstoneWhileSubscribedEndsWithResourceDeleted() async throws {
        let streamName = UUID().uuidString
        let client = KurrentDBClient(settings: settings)
        defer { client.shutdown() }

        try await client.streams(specified: streamName)
            .append(events: [EventData(eventType: "Before-Tombstone", data: Data(), contentType: .json)]) { $0.expectedRevision = .any }
        let subscription = try await client.streams(specified: streamName).subscribe { $0.revision = .start }

        try await client.streams(specified: streamName).tombstone()

        var delivered: [String] = []
        await #expect(throws: KurrentError.resourceDeleted(resource: streamName)) {
            for try await readEvent in subscription.events {
                delivered.append(readEvent.record.eventType)
            }
        }
        // The event appended before the tombstone arrives; the $streamDeleted marker does not.
        #expect(delivered == ["Before-Tombstone"])
    }

    @Test("Subscribing to an already tombstoned stream throws resourceDeleted")
    func testSubscribeToTombstonedStreamThrowsResourceDeleted() async throws {
        let streamName = UUID().uuidString
        let client = KurrentDBClient(settings: settings)
        defer { client.shutdown() }

        try await client.streams(specified: streamName)
            .append(events: [EventData(eventType: "Before-Tombstone", data: Data(), contentType: .json)]) { $0.expectedRevision = .any }
        try await client.streams(specified: streamName).tombstone()

        await #expect(throws: KurrentError.resourceDeleted(resource: streamName)) {
            let subscription = try await client.streams(specified: streamName).subscribe { $0.revision = .start }
            for try await _ in subscription.events {}
        }
    }

    @Test("A $streamDeleted event of another stream does not end a $all subscription")
    func testAllSubscriptionKeepsGoingPastATombstone() async throws {
        let streamName = UUID().uuidString
        let client = KurrentDBClient(settings: settings)
        defer { client.shutdown() }

        let subscription = try await client.allStreams.subscribe { $0.filter = .onStreamName(prefixes: streamName) }
        try await client.streams(specified: streamName)
            .append(events: [EventData(eventType: "Before-Tombstone", data: Data(), contentType: .json)]) { $0.expectedRevision = .any }
        try await client.streams(specified: streamName).tombstone()

        var delivered: [String] = []
        for try await readEvent in subscription.events {
            delivered.append(readEvent.record.eventType)
            if delivered.count == 2 { break }
        }
        #expect(delivered == ["Before-Tombstone", "$streamDeleted"])
        subscription.cancel()
    }
}
