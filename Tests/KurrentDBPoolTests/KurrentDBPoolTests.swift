import Foundation
import KurrentDB
import KurrentDBPool
import Testing

// 純 actor 記帳邏輯測試，不需要真的連線到任何 KurrentDB 實例——
// acquire()/release()/add()/remove() 都只操作記憶體狀態。
// borrow()/withBorrowedClient() 因為會實際打 readCluster() 探測存活，
// 需要一台真的跑起來的 KurrentDB，見 tasks/todo-kurrentdb-pool.md。
@Suite("KurrentDBPool Unit Tests", .serialized)
struct KurrentDBPoolTests {
    @Test("acquire() 回 nil 當池子沒有任何成員")
    func testEmptyPoolReturnsNil() async {
        let pool = KurrentDBPool(settings: [])
        let lease = await pool.acquire()
        #expect(lease == nil)
    }

    @Test("兩個成員可以同時被 acquire()，各拿到不同的 lease")
    func testConcurrentAcquireDistinctMembers() async {
        let pool = KurrentDBPool(settings: [.localhost(), .localhost(ports: 2114)])
        async let first = pool.acquire()
        async let second = pool.acquire()
        let (a, b) = await (first, second)
        #expect(a != nil)
        #expect(b != nil)
        #expect(a?.id != b?.id)
    }

    @Test("單一成員時，第二個 acquire() 會卡住直到 release() 才拿到同一個 lease")
    func testSingleMemberBlocksUntilRelease() async {
        let pool = KurrentDBPool(settings: [.localhost()])
        guard let first = await pool.acquire() else {
            Issue.record("預期第一次 acquire() 應該成功")
            return
        }

        let waiterTask = Task { await pool.acquire() }

        // 給 waiter 足夠時間真的掛起（如果實作有錯、沒有真的等待，這裡就會提早拿到結果）。
        try? await Task.sleep(for: .milliseconds(200))
        #expect(!waiterTask.isCancelled)

        await pool.release(first)
        let second = await waiterTask.value
        #expect(second?.id == first.id)
    }

    @Test("add() 能喚醒因為池子全滿而卡住的 acquire()")
    func testAddWakesWaiter() async {
        let pool = KurrentDBPool(settings: [.localhost()])
        guard let first = await pool.acquire() else {
            Issue.record("預期第一次 acquire() 應該成功")
            return
        }

        let waiterTask = Task { await pool.acquire() }
        try? await Task.sleep(for: .milliseconds(150))

        let newID = await pool.add(.localhost(ports: 2114))
        let waiterLease = await waiterTask.value
        #expect(waiterLease?.id == newID)

        await pool.release(first)
    }

    @Test("remove() 對忙碌成員只標記待移除，release() 之後才真的消失")
    func testRemoveBusyMemberDefersToRelease() async {
        let pool = KurrentDBPool(settings: [.localhost()])
        guard let lease = await pool.acquire() else {
            Issue.record("預期 acquire() 應該成功")
            return
        }

        await pool.remove(lease.id)
        await pool.release(lease)

        // 成員已經被移除，池子現在應該是空的——acquire() 立刻回 nil。
        let afterRemoval = await pool.acquire()
        #expect(afterRemoval == nil)
    }

    @Test("並發 acquire/release 不會讓同一個成員被兩個持有者同時租借")
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

/// 機率性防護網，不是形式證明：記錄任何「同一個 MemberID 在被標記釋放前又被別人拿到」的情況。
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
