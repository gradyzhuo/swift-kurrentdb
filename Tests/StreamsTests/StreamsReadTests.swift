//
//  StreamsReadTests.swift
//  swift-kurrentdb
//
//  Integration tests for stream read, delete, and tombstone operations
//  using the target-based API. Requires a running KurrentDB instance.
//

import Foundation
@testable import KurrentDB
import Testing

@Suite("Stream Read & Lifecycle Tests", .serialized)
struct StreamsReadTests: Sendable {
    let settings: ClientSettings

    init() {
        settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .certificate(source: .crtInBundle("ca", inBundle: .module)!)
    }

    // MARK: - Read forward

    @Test("Read events forward from the start returns all events in order")
    func testReadForwardFromStart() async throws {
        let streamName = UUID().uuidString
        let client = KurrentDBClient(settings: settings)
        let eventTypes = ["ReadFwd-A", "ReadFwd-B", "ReadFwd-C"]
        let events = eventTypes.map { EventData(eventType: $0, model: ["n": $0]) }

        try await client.streams(specified: streamName)
            .append(events: events) { $0.expectedRevision = .any }

        var readTypes: [String] = []
        let responses = try await client.streams(specified: streamName)
            .read { $0.direction = .forward; $0.revision = .start }
        for try await response in responses {
            if case let .event(event) = response {
                readTypes.append(event.record.eventType)
            }
        }

        #expect(readTypes == eventTypes)
        try await client.streams(specified: streamName).delete()
    }

    // MARK: - Read backward

    @Test("Read events backward from the end returns events in reverse order")
    func testReadBackwardFromEnd() async throws {
        let streamName = UUID().uuidString
        let client = KurrentDBClient(settings: settings)
        let eventTypes = ["ReadBwd-A", "ReadBwd-B", "ReadBwd-C"]
        let events = eventTypes.map { EventData(eventType: $0, model: ["n": $0]) }

        try await client.streams(specified: streamName)
            .append(events: events) { $0.expectedRevision = .any }

        var readTypes: [String] = []
        let responses = try await client.streams(specified: streamName)
            .read { $0.direction = .backward; $0.revision = .end }
        for try await response in responses {
            if case let .event(event) = response {
                readTypes.append(event.record.eventType)
            }
        }

        #expect(readTypes == eventTypes.reversed())
        try await client.streams(specified: streamName).delete()
    }

    // MARK: - Read with limit

    @Test("Read with limit returns at most the requested number of events")
    func testReadWithLimit() async throws {
        let streamName = UUID().uuidString
        let client = KurrentDBClient(settings: settings)
        let events = (1...5).map { EventData(eventType: "ReadLimit-\($0)", model: ["n": $0]) }

        try await client.streams(specified: streamName)
            .append(events: events) { $0.expectedRevision = .any }

        var count = 0
        let responses = try await client.streams(specified: streamName)
            .read { $0.direction = .forward; $0.revision = .start; $0.limit = 3 }
        for try await response in responses {
            if case .event = response { count += 1 }
        }

        #expect(count == 3)
        try await client.streams(specified: streamName).delete()
    }

    // MARK: - Read from specific revision

    @Test("Read from specific revision returns events starting at that position")
    func testReadFromSpecificRevision() async throws {
        let streamName = UUID().uuidString
        let client = KurrentDBClient(settings: settings)
        let events = (0..<5).map { EventData(eventType: "ReadRev-\($0)", model: ["i": $0]) }

        let appendResponse = try await client.streams(specified: streamName)
            .append(events: events) { $0.expectedRevision = .any }
        let lastRevision = try #require(appendResponse.currentRevision)

        // Read from revision 2 → should get events at revisions 2, 3, 4
        var readRevisions: [UInt64] = []
        let responses = try await client.streams(specified: streamName)
            .read { $0.direction = .forward; $0.revision = .specified(2) }
        for try await response in responses {
            if case let .event(event) = response {
                readRevisions.append(event.record.revision)
            }
        }

        #expect(readRevisions.first == 2)
        #expect(readRevisions.last == lastRevision)
        #expect(readRevisions.count == 3)
        try await client.streams(specified: streamName).delete()
    }

    // MARK: - Delete

    @Test("Deleting a stream makes it unreadable")
    func testDeleteStreamMakesItUnreadable() async throws {
        let streamName = UUID().uuidString
        let client = KurrentDBClient(settings: settings)

        try await client.streams(specified: streamName)
            .append(events: [EventData(eventType: "Delete-Event", data: Data(), contentType: .json)]) {
                $0.expectedRevision = .any
            }

        try await client.streams(specified: streamName).delete()

        await #expect(throws: KurrentError.resourceNotFound(reason: "The name '\(streamName)' of streams not found.")) {
            let responses = try await client.streams(specified: streamName).read()
            var iter = responses.makeAsyncIterator()
            _ = try await iter.next()
        }
    }

    // MARK: - Optimistic Concurrency

    @Test("Appending with a stale revision throws wrongExpectedVersion")
    func testAppendStaleRevision() async throws {
        let streamName = UUID().uuidString
        let client = KurrentDBClient(settings: settings)

        // Create the stream — revision lands at 0
        try await client.streams(specified: streamName)
            .append(events: [EventData(eventType: "RevConflict-Init", data: Data(), contentType: .json)]) {
                $0.expectedRevision = .any
            }

        // Attempt to append claiming revision 99 — stream is actually at 0
        await #expect {
            try await client.streams(specified: streamName)
                .append(events: [EventData(eventType: "RevConflict-Stale", data: Data(), contentType: .json)]) {
                    $0.expectedRevision = .at(99)
                }
        } throws: { error in
            guard case .wrongExpectedVersion = error as? KurrentError else { return false }
            return true
        }

        try await client.streams(specified: streamName).delete()
    }

    @Test("Appending with .noStream to an existing stream throws wrongExpectedVersion")
    func testAppendNoStreamToExistingStream() async throws {
        let streamName = UUID().uuidString
        let client = KurrentDBClient(settings: settings)

        // Create the stream — it now exists at revision 0
        try await client.streams(specified: streamName)
            .append(events: [EventData(eventType: "NoStream-Init", data: Data(), contentType: .json)]) {
                $0.expectedRevision = .any
            }

        // Attempt to append claiming the stream should not exist
        await #expect {
            try await client.streams(specified: streamName)
                .append(events: [EventData(eventType: "NoStream-After", data: Data(), contentType: .json)]) {
                    $0.expectedRevision = .noStream
                }
        } throws: { error in
            guard case .wrongExpectedVersion = error as? KurrentError else { return false }
            return true
        }

        try await client.streams(specified: streamName).delete()
    }

    @Test("Concurrent appends at the same revision — exactly one wins")
    func testConcurrentAppendsRevisionConflict() async throws {
        let streamName = UUID().uuidString
        let client = KurrentDBClient(settings: settings)

        // Establish the stream at revision 0
        try await client.streams(specified: streamName)
            .append(events: [EventData(eventType: "Concurrent-Init", data: Data(), contentType: .json)]) {
                $0.expectedRevision = .any
            }

        // Two writers both claim revision 0 — only one can succeed
        let results: [Result<Void, any Error>] = await withTaskGroup(
            of: Result<Void, any Error>.self,
            returning: [Result<Void, any Error>].self
        ) { group in
            for i in 0 ..< 2 {
                group.addTask {
                    do {
                        try await client.streams(specified: streamName)
                            .append(events: [EventData(eventType: "Concurrent-\(i)", data: Data(), contentType: .json)]) {
                                $0.expectedRevision = .at(0)
                            }
                        return .success(())
                    } catch {
                        return .failure(error)
                    }
                }
            }
            var collected: [Result<Void, any Error>] = []
            for await result in group { collected.append(result) }
            return collected
        }

        let successCount = results.filter { if case .success = $0 { true } else { false } }.count
        let conflictCount = results.filter {
            if case .failure(let e) = $0, case .wrongExpectedVersion = e as? KurrentError { true } else { false }
        }.count

        #expect(successCount == 1)
        #expect(conflictCount == 1)

        try await client.streams(specified: streamName).delete()
    }

    // MARK: - Tombstone

    @Test("Tombstoning a stream prevents further appends")
    func testTombstoneStreamPreventsAppend() async throws {
        let streamName = UUID().uuidString
        let client = KurrentDBClient(settings: settings)

        try await client.streams(specified: streamName)
            .append(events: [EventData(eventType: "Tombstone-Event", data: Data(), contentType: .json)]) {
                $0.expectedRevision = .any
            }

        try await client.streams(specified: streamName).tombstone()

        await #expect(throws: KurrentError.resourceDeleted(resource: streamName)) {
            try await client.streams(specified: streamName)
                .append(events: [EventData(eventType: "AfterTombstone", data: Data(), contentType: .json)]) {
                    $0.expectedRevision = .any
                }
        }
    }
}
