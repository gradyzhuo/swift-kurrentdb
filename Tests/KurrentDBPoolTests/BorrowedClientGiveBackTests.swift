import Foundation
import KurrentDB
import KurrentDBPool
import Synchronization
import Testing

// Offline: the borrowed clients point at localhost but never open a connection; only the
// pool's bookkeeping and the client's ConnectionProvider are exercised.
@Suite("BorrowedClient give-back", .serialized, .timeLimit(.minutes(1)))
struct BorrowedClientGiveBackTests {
    private func eventually(timeout: Duration = .seconds(10), _ condition: () async -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try await Task.sleep(for: .milliseconds(5))
        }
        return await condition()
    }

    /// A shutdown handler that blocks until `release()` is called, like a slow close handler of a
    /// leaked read, run by a shutdown that started on another thread.
    private final class SlowHandler: Sendable {
        let started = Mutex(false)
        let finished = Mutex(false)
        private let mayFinish = Mutex(false)

        func run() {
            started.withLock { $0 = true }
            while !mayFinish.withLock({ $0 }) { usleep(1_000) }
            finished.withLock { $0 = true }
        }

        func release() { mayFinish.withLock { $0 = true } }
    }

    /// Borrows the pool's only member, registers a slow handler on the borrowed client's
    /// connections and starts the client's own `shutdown()` on another thread, returning once that
    /// shutdown is inside the handler.
    private func borrowWithRacingShutdown(from pool: KurrentDBPool) async throws -> (BorrowedClient, KurrentDBPool.Lease, SlowHandler) {
        let lease = try #require(await pool.acquire())
        let borrowed = BorrowedClient(client: KurrentDBClient(settings: lease.settings), lease: lease)
        let handler = SlowHandler()
        _ = borrowed.client.selector.connections.registerShutdownHandler { handler.run() }
        let client = borrowed.client
        Thread { client.shutdown() }.start()
        #expect(try await eventually { handler.started.withLock { $0 } })
        return (borrowed, lease, handler)
    }

    @Test("giveBack() closes the client's connections and returns the instance only after the handlers of a racing shutdown have run")
    func giveBackWaitsForRacingShutdownHandlers() async throws {
        let pool = KurrentDBPool(settings: [.localhost()])
        let (borrowed, lease, handler) = try await borrowWithRacingShutdown(from: pool)

        let giveBack = Task { await borrowed.giveBack() }
        try await Task.sleep(for: .milliseconds(200))
        // The racing shutdown is still ending a call: the instance must not reach the next borrower.
        #expect(await pool.tryAcquire() == nil)

        handler.release()
        await giveBack.value
        #expect(handler.finished.withLock { $0 })
        #expect(borrowed.client.selector.connections.isShutdown)
        let next = await pool.tryAcquire()
        #expect(next?.id == lease.id)
    }

    @Test("A BorrowedClient released without giveBack() closes its connections and returns the instance only after the handlers of a racing shutdown have run")
    func deinitWaitsForRacingShutdownHandlers() async throws {
        let pool = KurrentDBPool(settings: [.localhost()])
        var borrowed: BorrowedClient?
        let lease: KurrentDBPool.Lease
        let handler: SlowHandler
        (borrowed, lease, handler) = try await borrowWithRacingShutdown(from: pool)
        let connections = try #require(borrowed).client.selector.connections
        borrowed = nil

        try await Task.sleep(for: .milliseconds(200))
        #expect(await pool.tryAcquire() == nil)

        handler.release()
        let next = Mutex<KurrentDBPool.Lease?>(nil)
        #expect(try await eventually {
            if let lease = await pool.tryAcquire() { next.withLock { $0 = lease } }
            return next.withLock { $0 != nil }
        })
        #expect(handler.finished.withLock { $0 })
        #expect(connections.isShutdown)
        #expect(next.withLock { $0?.id } == lease.id)
    }

    @Test("giveBack() without a racing shutdown closes the connections and returns the instance to the pool that lent it")
    func giveBackClosesConnectionsAndReturnsToItsPool() async throws {
        let pool = KurrentDBPool(settings: [.localhost()])
        let lease = try #require(await pool.acquire())
        let borrowed = BorrowedClient(client: KurrentDBClient(settings: lease.settings), lease: lease)

        await borrowed.giveBack()
        #expect(borrowed.isGivenBack)
        #expect(borrowed.client.selector.connections.isShutdown)
        #expect(await pool.tryAcquire()?.id == lease.id)
        await #expect(throws: KurrentError.connectionClosed) {
            try await borrowed.client.streams(specified: "any").append(events: [EventData(eventType: "T", model: ["k": "v"])])
        }
    }
}
