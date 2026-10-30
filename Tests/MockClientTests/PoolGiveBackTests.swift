//
//  PoolGiveBackTests.swift
//  swift-kurrentdb
//
//  No server needed: a KurrentDBPool whose only member is the in-process fake. Give-back of a
//  BorrowedClient whose read or subscription is still in progress.
//

import KurrentDB
import KurrentDBPool
import Synchronization
import Testing

@Suite("Pool give-back over the fake", .serialized, .timeLimit(.minutes(1)))
struct PoolGiveBackTests {
    private func eventually(timeout: Duration = .seconds(10), _ condition: () async -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try await Task.sleep(for: .milliseconds(5))
        }
        return await condition()
    }

    private func borrow(from fake: InProcessKurrentDB) async throws -> (KurrentDBPool, KurrentDBPool.Lease, BorrowedClient) {
        let pool = KurrentDBPool(settings: [fake.settings])
        let lease = try #require(await pool.acquire())
        return (pool, lease, BorrowedClient(client: KurrentDBClient(settings: lease.settings), lease: lease))
    }

    /// Takes one event of a read on a `.hold` script, gives the client back, then expects the read's
    /// next element to throw `connectionClosed`, the stream to be gone and the instance to be back.
    /// `isolation` picks the delivery path: `nil` the direct path, an actor the hand-off path.
    private func readInProgressAtGiveBack(isolation: isolated (any Actor)? = #isolation) async throws {
        let fake = InProcessKurrentDB(read: .events(3, then: .hold))
        let (pool, lease, borrowed) = try await borrow(from: fake)
        let iterator = borrowed.client.streams(specified: "orders").read().makeAsyncIterator()
        _ = try await iterator.next(isolation: isolation)
        #expect(await pool.tryAcquire() == nil)

        await borrowed.giveBack()
        #expect(await pool.tryAcquire()?.id == lease.id)
        await #expect(throws: KurrentError.connectionClosed) { _ = try await iterator.next(isolation: isolation) }
        #expect(try await eventually { fake.openStreams == 0 })
    }

    @Test("A read in progress at give-back (direct path) ends with connectionClosed; the instance is back once giveBack() returns")
    func readInProgressDirectPath() async throws {
        try await readInProgressAtGiveBack()
    }

    @Test("A read in progress at give-back (hand-off path, iterated on the main actor) ends with connectionClosed")
    @MainActor
    func readInProgressHandOffPath() async throws {
        try await readInProgressAtGiveBack()
    }

    @Test("A subscription in progress at give-back ends with connectionClosed; the instance is back once giveBack() returns")
    func subscriptionInProgress() async throws {
        // A subscription expects the server's confirmation first.
        var script = InProcessKurrentDB.ReadScript.events(3, then: .hold)
        script.messages.insert(.with { $0.confirmation = .with { $0.subscriptionID = "pool-give-back" } }, at: 0)
        let fake = InProcessKurrentDB(read: script)
        let (pool, lease, borrowed) = try await borrow(from: fake)
        let subscription = try await borrowed.client.streams(specified: "orders").subscribe()
        var events = subscription.events.makeAsyncIterator()
        _ = try await events.next()

        await borrowed.giveBack()
        #expect(await pool.tryAcquire()?.id == lease.id)
        // The fake sent three events before holding; the ones not yet taken may still be buffered.
        await #expect(throws: KurrentError.connectionClosed) {
            while try await events.next() != nil {}
        }
        #expect(try await eventually { fake.openStreams == 0 })
    }
}
