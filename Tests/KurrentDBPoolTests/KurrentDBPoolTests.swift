import Foundation
import KurrentDB
import KurrentDBPool
import Testing

// Tests of the actor's bookkeeping, which need no connection to any KurrentDB instance:
// acquire(), release(), add() and remove() only touch state in memory.
// borrow() and withBorrowedClient() probe for liveness with real RPCs, so they
// need a running KurrentDB; see tasks/todo-kurrentdb-pool.md and KurrentDBPoolLiveTests.swift.
@Suite("KurrentDBPool Unit Tests", .serialized)
struct KurrentDBPoolTests {
    @Test("acquire() returns nil when the pool has no members")
    func testEmptyPoolReturnsNil() async {
        let pool = KurrentDBPool(settings: [])
        let lease = await pool.acquire()
        #expect(lease == nil)
    }

    @Test("Two members can be acquired at once, each with its own lease")
    func testConcurrentAcquireDistinctMembers() async {
        let pool = KurrentDBPool(settings: [.localhost(), .localhost(ports: 2114)])
        async let first = pool.acquire()
        async let second = pool.acquire()
        let (a, b) = await (first, second)
        #expect(a != nil)
        #expect(b != nil)
        #expect(a?.id != b?.id)
    }

    @Test("With one member, a second acquire() waits until release() and then gets the same lease")
    func testSingleMemberBlocksUntilRelease() async {
        let pool = KurrentDBPool(settings: [.localhost()])
        guard let first = await pool.acquire() else {
            Issue.record("Expected the first acquire() to succeed")
            return
        }

        let waiterTask = Task { await pool.acquire() }

        // Give the waiter time to suspend (an implementation that did not wait would have a result by now).
        try? await Task.sleep(for: .milliseconds(200))
        #expect(!waiterTask.isCancelled)

        await pool.release(first)
        let second = await waiterTask.value
        #expect(second?.id == first.id)
    }

    @Test("add() wakes an acquire() waiting because every member was busy")
    func testAddWakesWaiter() async {
        let pool = KurrentDBPool(settings: [.localhost()])
        guard let first = await pool.acquire() else {
            Issue.record("Expected the first acquire() to succeed")
            return
        }

        let waiterTask = Task { await pool.acquire() }
        try? await Task.sleep(for: .milliseconds(150))

        let newID = await pool.add(.localhost(ports: 2114))
        let waiterLease = await waiterTask.value
        #expect(waiterLease?.id == newID)

        await pool.release(first)
    }

    @Test("remove() only marks a busy member for removal; it is gone after release()")
    func testRemoveBusyMemberDefersToRelease() async {
        let pool = KurrentDBPool(settings: [.localhost()])
        guard let lease = await pool.acquire() else {
            Issue.record("Expected acquire() to succeed")
            return
        }

        await pool.remove(lease.id)
        await pool.release(lease)

        // The member has been removed and the pool should be empty now: acquire() returns nil at once.
        let afterRemoval = await pool.acquire()
        #expect(afterRemoval == nil)
    }

    @Test("Concurrent acquire and release never lend one member to two holders at once")
    func testConcurrentAcquireReleaseNeverDoubleLeases() async {
        let pool = KurrentDBPool(settings: [.localhost(), .localhost(ports: 2114), .localhost(ports: 2115)])
        let detector = DoubleLeaseDetector()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<50 {
                group.addTask {
                    guard let lease = await pool.acquire() else { return }
                    await detector.acquire(lease.id)
                    try? await Task.sleep(for: .milliseconds(5))
                    await detector.release(lease.id)
                    await pool.release(lease)
                }
            }
        }

        let violations = await detector.violationCount
        #expect(violations == 0)
    }
}

/// A probabilistic safety net, not a proof: records every case of one MemberID handed to someone else before it was marked released.
private actor DoubleLeaseDetector {
    private var busy: Set<KurrentDBPool.MemberID> = []
    private(set) var violationCount = 0

    func acquire(_ id: KurrentDBPool.MemberID) {
        if busy.contains(id) { violationCount += 1 }
        busy.insert(id)
    }

    func release(_ id: KurrentDBPool.MemberID) {
        busy.remove(id)
    }
}
