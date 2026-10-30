//
//  InProcessKurrentDBTests.swift
//  swift-kurrentdb
//
//  No server needed: the client runs against `InProcessKurrentDB`.
//

import GRPCCore
import Testing
@testable import KurrentDB

@Suite("In-process fake node", .serialized, .timeLimit(.minutes(1)))
struct InProcessKurrentDBTests {
    /// Waits until the condition holds or the timeout passes.
    private func eventually(timeout: Duration = .seconds(10), _ condition: () async -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return await condition()
    }

    @Test("A lazy read of three scripted events delivers them in order and ends")
    func lazyReadOfScriptedEvents() async throws {
        let fake = InProcessKurrentDB(read: .events(3))
        let client = KurrentDBClient(settings: fake.settings)
        defer { try? client.shutdown() }
        var revisions: [UInt64] = []
        for try await response in client.streams(specified: "orders").read() {
            try revisions.append(response.event.record.revision)
        }
        #expect(revisions == [0, 1, 2])
        #expect(fake.readsStarted == 1)
        #expect(try await eventually { fake.openStreams == 0 })
    }

    @Test("A read broken off on a .hold script leaves no open stream, and none after the connection is closed")
    func brokenHoldReadClosesWithTheConnection() async throws {
        let fake = InProcessKurrentDB(read: .events(3, then: .hold))
        let client = KurrentDBClient(settings: fake.settings)
        for try await _ in client.streams(specified: "orders").read() {
            break
        }
        #expect(fake.readsStarted == 1)
        try client.shutdown()
        #expect(try await eventually { fake.openStreams == 0 })
    }

    @Test("With maxConcurrentStreams, a stream beyond the limit waits for a slot until its task is cancelled")
    func streamBeyondTheLimitWaits() async throws {
        let fake = InProcessKurrentDB(read: .events(3, then: .hold), maxConcurrentStreams: 1)
        // No call timeout: the held read must keep its slot for the whole test, so the second read is
        // ended by cancelling its task instead of by a deadline both reads would share.
        let client = KurrentDBClient(settings: fake.settings)
        defer { try? client.shutdown() }
        // Discovery runs on the main connection; the first read holds the read connection's one slot.
        let held = client.streams(specified: "orders").read().makeAsyncIterator()
        _ = try await held.next()
        #expect(fake.openStreams == 1)
        let discoveries = fake.discoveries
        let start = ContinuousClock.now
        let waiting = Task {
            for try await _ in client.streams(specified: "orders").read() {}
        }
        try await Task.sleep(for: .milliseconds(300))
        #expect(fake.readsStarted == 1)
        waiting.cancel()
        await #expect(throws: CancellationError.self) { try await waiting.value }
        #expect(ContinuousClock.now - start >= .milliseconds(300))
        #expect(fake.readsStarted == 1)
        #expect(fake.discoveries == discoveries)   // a cancelled wait is never retried
        withExtendedLifetime(held) {}
    }

}
