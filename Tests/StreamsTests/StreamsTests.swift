//
//  StreamsTests.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2023/10/28.
//

import Foundation
@testable import KurrentDB
import Logging
import Testing

package enum TestingError: Error {
    case exception(String)
}

@Suite("EventStoreDB Stream Tests", .serialized)
struct StreamTests: Sendable {
    let settings: ClientSettings

    init() {
        settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .certificate(source: .crtInBundle("ca", inBundle: .module)!)
    }

    @Test("Stream should be not found and throw an error.")
    func testStreamNotFound() async throws {
        let client = KurrentDBClient(settings: settings)
        let streamIdentifier = UUID().uuidString
        await #expect(throws: KurrentError.resourceNotFound(reason: "The name '\(streamIdentifier)' of streams not found.")) {
            let responses = client.streams(specified: streamIdentifier).read()
            let responsesIterator = responses.makeAsyncIterator()
            _ = try await responsesIterator.next()
        }
    }

    @Test("It should succeed when appending events to a stream.", arguments: [
        [
            EventData(eventType: "AppendEvent-AccountCreated", model: ["Description": "Gears of War 4"]),
            EventData(eventType: "AppendEvent-AccountDeleted", model: ["Description": "Gears of War 4"]),
        ],
    ])
    func testAppendEvent(events: [EventData]) async throws {
        let streamIdentifier = StreamIdentifier(name: UUID().uuidString)
        let client = KurrentDBClient(settings: settings)

        let appendResponse = try await client.streams(specified: streamIdentifier.name)
            .append(events: events) { $0.expectedRevision = .any }

        let appendedRevision = try #require(appendResponse.currentRevision)
        let readResponses = client.streams(specified: streamIdentifier.name)
            .read { $0.direction = .forward; $0.revision = .specified(appendedRevision) }

        let firstResponse = try await readResponses.first { _ in true }
        guard case let .event(readEvent: readEvent) = firstResponse,
              let readPosition = readEvent.commitPosition,
              let position = appendResponse.position
        else {
            throw TestingError.exception("readResponse.content or appendResponse.position is not Event or Position")
        }

        #expect(readPosition == position)

        try await client.streams(specified: streamIdentifier.name).delete()
    }

    @Test("It should succeed when appending events to streams.",
          .enabled(if: ProcessInfo.processInfo.environment["KURRENTDB_SUPPORTS_MULTI_STREAMS"] == "true"),
          arguments: [
        [
            try StreamEvent(stream: "AppendSessionStream-\(UUID().uuidString)", eventData: EventData(eventType: "AppendEvent-AccountCreated", model: ["Description": "Gears of War 4"]), expectedRevision: .any),

            try StreamEvent(stream: "AppendSessionStream-\(UUID().uuidString)", eventData: EventData(eventType: "AppendEvent-AccountDeleted", model: ["Description": "Gears of War 4"]), expectedRevision: .any),
        ],
    ])
    func testMultipleAppendToStreams(events: [StreamEvent]) async throws {
        let client = KurrentDBClient(settings: settings)

        let appendResponse = try await client.multiStreams.append(events: events)

        let positions = try await withThrowingTaskGroup(of: (StreamPosition, StreamPosition?).self, returning: [(StreamPosition, StreamPosition?)].self) { group in
            for event in events {
                group.addTask {
                    let result = try #require(appendResponse.results.first {
                        $0.streamIdentifier == event.streamIdentifier
                    })
                    let appendedRevision = result.currentRevision

                    let readResponses = client.streams(specified: event.streamIdentifier.name)
                        .read { $0.direction = .forward; $0.revision = .specified(appendedRevision) }

                    let firstResponse = try await readResponses.first { _ in true }
                    guard case let .event(readEvent: readEvent) = firstResponse,
                          let readPosition = readEvent.commitPosition
                    else {
                        throw TestingError.exception("readResponse.content or appendResponse.position is not Event or Position")
                    }

                    try await client.streams(specified: event.streamIdentifier.name).delete()
                    return (readPosition, result.position)
                }
            }

            return try await group.reduce(into: .init()) { partialResult, item in
                partialResult.append(item)
            }
        }

        let maxPosition = positions.max {
            $0.0.commit < $1.0.commit
        }.flatMap(\.0.commit)

        #expect(maxPosition == appendResponse.position.commit)
    }

    @Test("It should succeed when setting metadata to a stream.")
    func testMetadata() async throws {
        let streamIdentifier = StreamIdentifier(name: UUID().uuidString)
        let metadata = StreamMetadata()
            .cacheControl(.seconds(3))
            .maxAge(.seconds(30))
            .acl(.stream(StreamMetadata.StreamAcl.defaults.readRoles(["$all"]).metaWriteRoles(["$admins"])))

        let client = KurrentDBClient(settings: settings)

        try await client.streams(specified: streamIdentifier.name).setMetadata(metadata: metadata)

        let responseMetadata = try #require(try await client.streams(specified: streamIdentifier.name).getMetadata())
        #expect(metadata == responseMetadata)

        // The bytes stored in $$<stream> carry $maxAge in whole seconds.
        let metadataStream = client.streams(specified: "$$\(streamIdentifier.name)")
        let storedResponse = try await metadataStream.read {
            $0.direction = .backward
            $0.revision = .end
            $0.limit = 1
        }.first {
            if case .event = $0 { true } else { false }
        }
        guard case let .event(storedEvent) = storedResponse else {
            Issue.record("No metadata event in $$\(streamIdentifier.name).")
            return
        }
        #expect(String(decoding: storedEvent.record.data, as: UTF8.self).contains(#""$maxAge":30"#))

        // Metadata written by another client: system fields and custom keys at the top level.
        let otherClientJSON = #"{"$maxCount":10,"$maxAge":60,"tenant":"acme","retries":3}"#
        try await metadataStream.append(events: [
            EventData(eventType: "$metadata", payload: .data(Data(otherClientJSON.utf8), .json)),
        ])
        let otherClientMetadata = try #require(try await client.streams(specified: streamIdentifier.name).getMetadata())
        #expect(otherClientMetadata.maxAge == .seconds(60))
        #expect(otherClientMetadata.maxCount == 10)
        let object = try JSONDecoder().decode([String: PropertyValue].self, from: otherClientMetadata.data)
        #expect(object["tenant"] == .string("acme"))
        #expect(object["retries"] == .integer(3))

        try await client.streams(specified: streamIdentifier.name).delete()
    }

    /// The data of the latest event in `$$<stream>`, as the server stores it.
    private func storedMetadata(of stream: String, client: KurrentDBClient) async throws -> Data? {
        let response = try await client.streams(specified: "$$\(stream)").read {
            $0.direction = .backward
            $0.revision = .end
            $0.limit = 1
        }.first {
            if case .event = $0 { true } else { false }
        }
        guard case let .event(event) = response else { return nil }
        return event.record.data
    }

    @Test("setMetadata stores metadata.data byte for byte, unknown keys in their order")
    func testSetMetadataSendsDataAsIs() async throws {
        let stream = UUID().uuidString
        let client = KurrentDBClient(settings: settings)
        let json = #"{"zeta":1,"$future":{"b":2,"a":1},"alpha":"x","$maxCount":3}"#
        let metadata = try StreamMetadata(data: Data(json.utf8))
        try await client.streams(specified: stream).setMetadata(metadata: metadata)
        #expect(try await storedMetadata(of: stream, client: client) == Data(json.utf8))
        #expect(try await client.streams(specified: stream).getMetadata()?.data == Data(json.utf8))
        // The stream holds metadata only, so a delete may find nothing to delete.
        _ = try? await client.streams(specified: stream).delete()
    }

    @Test("Metadata with a repeated key reads and rewrites as the server applies it: the last occurrence")
    func testRepeatedKeyRewriteKeepsEvents() async throws {
        let stream = UUID().uuidString
        let client = KurrentDBClient(settings: settings)
        let events = (0 ..< 5).map { EventData(eventType: "RepeatedKey", model: ["index": $0]) }
        try await client.streams(specified: stream).append(events: events)
        // Another client stored a repeated key; the server applies the last one, 100.
        try await client.streams(specified: "$$\(stream)").append(events: [
            EventData(eventType: "$metadata", payload: .data(Data(#"{"$maxCount":2,"$maxCount":100}"#.utf8), .json)),
        ])

        let stored = try #require(try await client.streams(specified: stream).getMetadata())
        #expect(stored.maxCount == 100)
        try await client.streams(specified: stream).setMetadata(metadata: stored.cacheControl(.seconds(5)))

        // Reading the first occurrence would have written $maxCount 2 back and hidden 3 events.
        let rewritten = try #require(try await storedMetadata(of: stream, client: client))
        #expect(String(decoding: rewritten, as: UTF8.self) == #"{"$cacheControl":5,"$maxCount":100}"#)
        var count = 0
        for try await _ in client.streams(specified: stream).read() {
            count += 1
        }
        #expect(count == 5)
        try await client.streams(specified: stream).delete()
    }

    @Test("It should succeed when subscribing to a stream.")
    func testSubscribe() async throws {
        let streamIdentifier = StreamIdentifier(name: UUID().uuidString)
        let client = KurrentDBClient(settings: settings)

        let subscription = try await client.streams(specified: streamIdentifier.name).subscribe()
        let response = try await client.streams(specified: streamIdentifier.name).append(events: [
            .init(eventType: "Subscribe-AccountCreated", model: ["Description": "Gears of War 10"]),
        ]) { $0.expectedRevision = .any }

        let firstEvent: ReadEvent? = try await subscription.events.first { _ in
            true
        }

        let lastEventRevision = try #require(firstEvent?.record.revision)
        #expect(response.currentRevision == lastEventRevision)
        try await client.streams(specified: streamIdentifier.name).delete()
    }

    @Test("It should succeed when subscribing to all streams.")
    func testSubscribeAll() async throws {
        let streamIdentifier = StreamIdentifier(name: UUID().uuidString)
        let eventForTesting = EventData(
            eventType: "SubscribeAll-AccountCreated", model: ["Description": "Gears of War 10"]
        )
        let client = KurrentDBClient(settings: settings)

        let subscription = try await client.allStreams.subscribe {
            $0.filter = .onEventType(regex: "SubscribeAll-AccountCreated")
            $0.position = .end
        }
        let response = try await client.streams(specified: streamIdentifier.name)
            .append(events: [eventForTesting]) { $0.expectedRevision = .any }

        var lastEvent: ReadEvent?
        for try await event in subscription.events {
            if event.record.eventType == eventForTesting.eventType {
                lastEvent = event
                break
            }
        }

        let lastEventPosition = try #require(lastEvent?.record.position)
        #expect(response.position?.commit == lastEventPosition.commit)
        try await client.streams(specified: streamIdentifier.name).delete()
    }

    @Test("It should succeed when subscribing to all streams with an event type filter.")
    func testSubscribeAllWithFilter() async throws {
        let streamIdentifier = StreamIdentifier(name: UUID().uuidString)
        let eventForTesting = EventData(
            eventType: "SubscribeAll-AccountCreated", model: ["Description": "Gears of War 10"]
        )
        let client = KurrentDBClient(settings: settings)

        let filter: StreamFilter = .onEventType(prefixes: "SubscribeAll-AccountCreated")
        let subscription = try await client.allStreams.subscribe {
            $0.filter = filter
            $0.position = .end
        }

        let response = try await client.streams(specified: streamIdentifier.name)
            .append(events: [eventForTesting]) { $0.expectedRevision = .any }

        var lastEvent: ReadEvent?
        for try await event in subscription.events {
            lastEvent = event
            break
        }

        let lastEventPosition = try #require(lastEvent?.record.position)
        #expect(response.position?.commit == lastEventPosition.commit)
        try await client.streams(specified: streamIdentifier.name).delete()
    }

    @Test("It should succeed when subscribing to all streams by excluding system events.")
    func testSubscribeAllExcludeSystemEvents() async throws {
        let streamIdentifier = StreamIdentifier(name: UUID().uuidString)
        let eventForTesting = EventData(
            eventType: "SubscribeAll-AccountCreated", model: ["Description": "Gears of War 10"]
        )
        let client = KurrentDBClient(settings: settings)

        let filter: StreamFilter = .excludeSystemEvents()
        let subscription = try await client.allStreams.subscribe {
            $0.filter = filter
            $0.position = .end
        }

        let response = try await client.streams(specified: streamIdentifier.name)
            .append(events: [eventForTesting]) { $0.expectedRevision = .any }

        var lastEvent: ReadEvent?
        for try await event in subscription.events {
            lastEvent = event
            break
        }

        let lastEventPosition = try #require(lastEvent?.record.position)
        #expect(response.position?.commit == lastEventPosition.commit)
        try await client.streams(specified: streamIdentifier.name).delete()
    }

    @Test("It should succeed when subscribing to all streams with a stream name filter.")
    func testSubscribeFilterOnStreamName() async throws {
        let streamIdentifier = StreamIdentifier(name: UUID().uuidString)
        let eventForTesting = EventData(
            eventType: "SubscribeAll-AccountCreated", model: ["Description": "Gears of War 10"]
        )
        let client = KurrentDBClient(settings: settings)

        let filter: StreamFilter = .onStreamName(prefixes: streamIdentifier.name)
        let subscription = try await client.allStreams.subscribe {
            $0.filter = filter
            $0.position = .end
        }

        let response = try await client.streams(specified: streamIdentifier.name)
            .append(events: [eventForTesting]) { $0.expectedRevision = .any }

        var lastEvent: ReadEvent?
        for try await event in subscription.events {
            lastEvent = event
            break
        }

        let lastEventPosition = try #require(lastEvent?.record.position)
        #expect(response.position?.commit == lastEventPosition.commit)
        try await client.streams(specified: streamIdentifier.name).delete()
    }

    @Test("It should fail when subscribing to all streams with an incorrect stream name filter.")
    func testSubscribeFilterFailedOnStreamName() async throws {
        let streamIdentifier = StreamIdentifier(name: UUID().uuidString)
        let eventForTesting = EventData(
            eventType: "SubscribeAll-AccountCreated", model: ["Description": "Gears of War 10"]
        )
        let client = KurrentDBClient(settings: settings)

        let filter: StreamFilter = .onStreamName(prefixes: "wrong")
        let subscription = try await client.allStreams.subscribe {
            $0.filter = filter
            $0.position = .end
        }

        _ = try await client.streams(specified: streamIdentifier.name)
            .append(events: [eventForTesting]) { $0.expectedRevision = .any }

        Task {
            try? await Task.sleep(for: .microseconds(500))
            subscription.cancel()
        }

        var receivedEvent = false
        for try await _ in subscription.events {
            receivedEvent = true
            break
        }
        #expect(!receivedEvent)
    }

    @Test("It should return only matching events when reading $all with an event type filter.")
    func testReadAllWithEventTypeFilter() async throws {
        let client = KurrentDBClient(settings: settings)
        let unique = "ReadAllFilter-\(UUID().uuidString)"
        let streamIdentifier = StreamIdentifier(name: UUID().uuidString)

        let events = [
            EventData(eventType: "\(unique)-Created", model: ["k": "v1"]),
            EventData(eventType: "\(unique)-Updated", model: ["k": "v2"]),
        ]
        _ = try await client.streams(specified: streamIdentifier.name)
            .append(events: events) { $0.expectedRevision = .any }

        let responses = client.allStreams.read {
            $0.filter = .onEventType(prefixes: unique)
            $0.position = .start
            $0.direction = .forward
        }

        var matched: [RecordedEvent] = []
        for try await response in responses {
            let record = try response.event.record
            matched.append(record)
        }

        // Every returned event matches the filter, and both appended events are present.
        #expect(matched.allSatisfy { $0.eventType.hasPrefix(unique) })
        let ids = Set(matched.map(\.id))
        #expect(events.allSatisfy { ids.contains($0.id) })

        try await client.streams(specified: streamIdentifier.name).delete()
    }

    @Test("It should return only matching events when reading $all with a stream name filter.")
    func testReadAllWithStreamNameFilter() async throws {
        let client = KurrentDBClient(settings: settings)
        let prefix = "ReadAllStreamFilter-\(UUID().uuidString)"
        let targetName = "\(prefix)-orders"
        let otherName = UUID().uuidString

        let targetEvent = EventData(eventType: "AccountCreated", model: ["k": "target"])
        let otherEvent = EventData(eventType: "AccountCreated", model: ["k": "other"])

        _ = try await client.streams(specified: targetName)
            .append(events: [targetEvent]) { $0.expectedRevision = .any }
        _ = try await client.streams(specified: otherName)
            .append(events: [otherEvent]) { $0.expectedRevision = .any }

        let responses = client.allStreams.read {
            $0.filter = .onStreamName(prefixes: prefix)
            $0.position = .start
            $0.direction = .forward
        }

        var matched: [RecordedEvent] = []
        for try await response in responses {
            let record = try response.event.record
            matched.append(record)
        }

        let ids = Set(matched.map(\.id))
        #expect(ids.contains(targetEvent.id))
        #expect(!ids.contains(otherEvent.id))

        try await client.streams(specified: targetName).delete()
        try await client.streams(specified: otherName).delete()
    }

    @Test("It should not fail when a filtered $all read emits checkpoints.")
    func testReadAllFilterWithCheckpoints() async throws {
        let client = KurrentDBClient(settings: settings)
        let unique = "ReadAllCheckpoint-\(UUID().uuidString)"
        let streamIdentifier = StreamIdentifier(name: UUID().uuidString)

        let events = [
            EventData(eventType: "\(unique)-Created", model: ["k": "v1"]),
            EventData(eventType: "\(unique)-Updated", model: ["k": "v2"]),
        ]
        _ = try await client.streams(specified: streamIdentifier.name)
            .append(events: events) { $0.expectedRevision = .any }

        // A low checkpoint multiplier forces the server to interleave checkpoint frames while
        // scanning the sparse filter across all of $all — these must be skipped, not thrown.
        let responses = client.allStreams.read {
            $0.filter = .onEventType(prefixes: unique).checkpointIntervalMultiplier(1)
            $0.position = .start
            $0.direction = .forward
        }

        var matched: [RecordedEvent] = []
        for try await response in responses {
            matched.append(try response.event.record)
        }

        let ids = Set(matched.map(\.id))
        #expect(events.allSatisfy { ids.contains($0.id) })
        #expect(matched.allSatisfy { $0.eventType.hasPrefix(unique) })

        try await client.streams(specified: streamIdentifier.name).delete()
    }

    @Test("getMetadata throws for metadata the server ignores as a whole, as a 2.x client wrote it", arguments: [
        #"{"$maxCount":2,"$maxAge":[3,4659767778871345152]}"#,
        #"{"$maxCount":2,"$acl":"$userStreamAcl"}"#,
    ])
    func testGetMetadataThrowsForIgnoredMetadata(json: String) async throws {
        let stream = UUID().uuidString
        let client = KurrentDBClient(settings: settings)
        let events = (0 ..< 5).map { EventData(eventType: "IgnoredMetadata", model: ["index": $0]) }
        try await client.streams(specified: stream).append(events: events)
        try await client.streams(specified: "$$\(stream)").append(events: [
            EventData(eventType: "$metadata", payload: .data(Data(json.utf8), .json)),
        ])

        // The server ignores the whole object, so $maxCount 2 does not apply.
        var count = 0
        for try await _ in client.streams(specified: stream).read() {
            count += 1
        }
        #expect(count == 5)
        await #expect {
            try await client.streams(specified: stream).getMetadata()
        } throws: { error in
            guard case .internalParsingError = error as? KurrentError else { return false }
            return true
        }
        _ = try? await client.streams(specified: stream).delete()
    }

    @Test("acl(.serverDefault) writes metadata without $acl and keeps the other keys")
    func testServerDefaultAclRemovesAcl() async throws {
        let stream = UUID().uuidString
        let client = KurrentDBClient(settings: settings)
        let roles = StreamMetadata.StreamAcl.defaults.readRoles(["$admins"]).metaWriteRoles(["$admins"])
        try await client.streams(specified: stream).setMetadata(metadata: StreamMetadata().maxCount(3).acl(.stream(roles)))
        let stored = try #require(try await client.streams(specified: stream).getMetadata())
        #expect(stored.acl == .stream(roles))

        try await client.streams(specified: stream).setMetadata(metadata: stored.acl(.serverDefault))
        #expect(try await storedMetadata(of: stream, client: client) == Data(#"{"$maxCount":3}"#.utf8))
        #expect(try await client.streams(specified: stream).getMetadata()?.acl == .serverDefault)
        _ = try? await client.streams(specified: stream).delete()
    }

    @Test("A stream's first ACL starts from StreamAcl.defaults, and .defaults hands one permission back to $settings")
    func testFirstStreamAcl() async throws {
        let stream = UUID().uuidString
        let client = KurrentDBClient(settings: settings)
        let orders = client.streams(specified: stream)
        try await orders.append(events: [EventData(eventType: "FirstAcl", model: ["index": 0])])

        let roles = StreamMetadata.StreamAcl.defaults.writeRoles(["ops"]).metaWriteRoles(["$admins"])
        let first = StreamMetadata().acl(.stream(roles))
        try await orders.setMetadata(metadata: first)
        #expect(try await storedMetadata(of: stream, client: client) == Data(#"{"$acl":{"$mw":["$admins"],"$w":["ops"]}}"#.utf8))

        // admin is a member of $admins, which always has access: the stream still works.
        try await orders.append(events: [EventData(eventType: "FirstAcl", model: ["index": 1])])
        var count = 0
        for try await _ in orders.read() {
            count += 1
        }
        #expect(count == 2)

        let stored = try #require(try await orders.getMetadata())
        guard case let .stream(current) = stored.acl else {
            Issue.record("Expected a stream ACL, got \(String(describing: stored.acl)).")
            return
        }
        #expect(current == roles)
        #expect(current.readRoles == .defaults)
        try await orders.setMetadata(metadata: stored.acl(.stream(current.writeRoles(.defaults))))
        #expect(try await storedMetadata(of: stream, client: client) == Data(#"{"$acl":{"$mw":["$admins"]}}"#.utf8))
        _ = try? await orders.delete()
    }
    @Test("The server applies the metadata setMetadata writes: maxCount, durations and the ACL together")
    func testMetadataIsApplied() async throws {
        let stream = UUID().uuidString
        let client = KurrentDBClient(settings: settings)
        let orders = client.streams(specified: stream)
        try await orders.append(events: (0 ..< 3).map { EventData(eventType: "Applied", model: ["index": $0]) })

        // 2.6.1 wrote maxAge and the ACL in shapes that made the server ignore all of this.
        let metadata = StreamMetadata()
            .maxCount(1)
            .maxAge(.seconds(3600))
            .cacheControl(.seconds(3))
            .acl(.stream(StreamMetadata.StreamAcl.defaults.readRoles(["$admins"])))
        try await orders.setMetadata(metadata: metadata)
        #expect(try await storedMetadata(of: stream, client: client) == metadata.data)

        var indices: [Int] = []
        for try await response in orders.read() {
            if case let .event(event) = response {
                try indices.append(#require(try JSONDecoder().decode([String: Int].self, from: event.record.data)["index"]))
            }
        }
        #expect(indices == [2])

        let loginName = "metadata-\(UUID().uuidString.prefix(8))"
        _ = try await client.users.create(loginName: loginName, password: "Password123!", fullName: "Metadata Test", groups: [.ops])
        let user = KurrentDBClient(settings: settings.authenticated(.credentials(username: loginName, password: "Password123!")))
        await #expect(throws: KurrentError.accessDenied) {
            for try await _ in user.streams(specified: stream).read() {}
        }

        try await client.user(loginName).disable()
        _ = try? await orders.delete()
    }
}
