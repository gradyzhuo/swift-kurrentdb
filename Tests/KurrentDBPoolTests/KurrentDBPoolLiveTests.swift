import Foundation
import KurrentDB
import KurrentDBPool
import Testing

/// These tests connect to the containers behind KurrentDBPool.shared, named by KURRENTDB_POOL_URLS,
/// through borrow() and withBorrowedClient(), the two entry points that send real RPCs. They are kept
/// apart from the tests of the actor's bookkeeping in KurrentDBPoolTests.swift.
///
/// Without KURRENTDB_POOL_URLS the whole suite is skipped with .enabled(if:), instead of every
/// test recording a failure because it gets no client: a plain `swift test` where no set of
/// independent KurrentDB instances was prepared (a developer's machine, an offline CI job) should
/// skip this suite cleanly and not return a non-zero result.
@Suite(
    "KurrentDBPool Live Tests",
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["KURRENTDB_POOL_URLS"] != nil)
)
struct KurrentDBPoolLiveTests {
    @Test("withBorrowedClient lends a client that can send RPCs")
    func testWithBorrowedClientWorks() async throws {
        let members = try await withBorrowedClient { borrowed in
            try await borrowed.client.readCluster()
        }
        #expect(members != nil)
        #expect(members?.isEmpty == false)
    }

    @Test("After the borrow, isGivenBack is true and the client's connections are closed: later calls throw connectionClosed")
    func testIsGivenBackClosesTheClient() async {
        var capturedBorrowed: BorrowedClient?
        _ = await withBorrowedClient { borrowed in
            capturedBorrowed = borrowed
        }

        guard let borrowed = capturedBorrowed else {
            Issue.record("Expected a BorrowedClient")
            return
        }

        #expect(borrowed.isGivenBack)
        // Give-back closes the client, so a client kept past the closure never reaches the instance
        // again, which the next borrower may hold.
        await #expect(throws: KurrentError.connectionClosed) {
            try await borrowed.client.readCluster()
        }
    }

    @Test("A ReadCall and a facade returned from withBorrowedClient end with connectionClosed")
    func leakedCallsEndWithConnectionClosed() async throws {
        let leaked = await withBorrowedClient { borrowed in
            (call: borrowed.client.streams(specified: "any").read(), streams: borrowed.client.streams(specified: "any"))
        }
        let (call, streams) = try #require(leaked)
        await #expect(throws: KurrentError.connectionClosed) { for try await _ in call {} }
        await #expect(throws: KurrentError.connectionClosed) { _ = try await streams.append(events: [EventData(eventType: "T", model: ["k": "v"])]) }
    }

    @Test("Two members borrowed at once do not see each other's events (isolation)")
    func testTwoSimultaneousBorrowsAreIsolated() async throws {
        // This test needs at least two members by nature: only then can the second borrow() get a
        // different one from the first. With one member, the acquire() inside the second borrow() queues,
        // since the pool has members but all are busy, and waits forever for a release() only first would cause.
        // Check the count first and skip explicitly when it is too low, so the run does not hang here.
        guard await KurrentDBPool.shared.count >= 2 else {
            return
        }

        guard let first = await KurrentDBPool.borrow() else {
            Issue.record("Expected to borrow the first member")
            return
        }
        guard let second = await KurrentDBPool.borrow() else {
            await first.giveBack()
            Issue.record("Expected to borrow the second member: the pool needs at least two")
            return
        }

        let streamName = "kurrentdb-pool-isolation-\(UUID().uuidString)"
        let events = [EventData(eventType: "PoolIsolationTest", model: ["ok": true])]

        try await first.client.streams(specified: streamName)
            .append(events: events) { $0.expectedRevision = .any }

        var readBackOnFirst: [String] = []
        let responses = first.client.streams(specified: streamName).read {
            $0.direction = .forward
            $0.revision = .start
        }
        for try await response in responses {
            if case let .event(event) = response {
                readBackOnFirst.append(event.record.eventType)
            }
        }
        #expect(readBackOnFirst == ["PoolIsolationTest"])

        await #expect(throws: KurrentError.resourceNotFound(
            reason: "The name '\(streamName)' of streams not found."
        )) {
            let iterator = second.client.streams(specified: streamName).read().makeAsyncIterator()
            _ = try await iterator.next()
        }

        try await first.client.streams(specified: streamName).delete()
        await first.giveBack()
        await second.giveBack()
    }

    @Test("borrow() returns nil after trying an only candidate that cannot be reached, without locking itself up (regression)")
    func testBorrowDoesNotDeadlockWithSingleDeadCandidate() async {
        // Borrow every member shared already has, so the bad address added below is the only
        // candidate that can be drawn: that makes sure borrow() really meets it and does not
        // go around it to a live member.
        var heldLive: [KurrentDBPool.Lease] = []
        while let lease = await KurrentDBPool.shared.tryAcquire() {
            heldLive.append(lease)
        }

        let deadID = await KurrentDBPool.shared.add(.remote(.init(host: "127.0.0.1", port: 1), secure: false))

        let result = await KurrentDBPool.borrow(maxAttempts: 3)
        #expect(result == nil)

        await KurrentDBPool.shared.remove(deadID)
        for lease in heldLive { await lease.giveBack() }
    }

    @Test("Candidate rotation keeps bad members ahead of a healthy one from blocking it forever (regression)")
    func testBorrowRotatesPastPersistentlyBadCandidates() async {
        // Borrow every member there already is, so the candidates added next are the only ones visible.
        var heldLive: [KurrentDBPool.Lease] = []
        while let lease = await KurrentDBPool.shared.tryAcquire() {
            heldLive.append(lease)
        }

        guard let goodSettings = heldLive.first?.settings else {
            Issue.record("At least one live member is needed as the source of settings")
            return
        }

        // The order matters: the 3 unreachable ones go in first and the healthy one last. Before the fix,
        // firstIdleID() scanned in insertion order, the healthy member was always last, and
        // giveBack() returned the bad members to the same places, so every
        // borrow() tested the same 3 bad members again and never reached the good one.
        var deadIDs: [KurrentDBPool.MemberID] = []
        for _ in 0..<3 {
            deadIDs.append(await KurrentDBPool.shared.add(.remote(.init(host: "127.0.0.1", port: 1), secure: false)))
        }
        let goodID = await KurrentDBPool.shared.add(goodSettings)

        // 4 candidates and maxAttempts=3: two calls (6 attempts) at most go round all of them.
        var succeeded = false
        for _ in 0..<8 {
            if let borrowed = await KurrentDBPool.borrow(maxAttempts: 3) {
                succeeded = true
                await borrowed.giveBack()
                break
            }
        }
        #expect(succeeded)

        for id in deadIDs { await KurrentDBPool.shared.remove(id) }
        await KurrentDBPool.shared.remove(goodID)
        for lease in heldLive { await lease.giveBack() }
    }
}
