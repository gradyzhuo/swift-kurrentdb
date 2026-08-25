import Foundation
import KurrentDB
import KurrentDBPool
import Testing

/// 這些測試會實際連線到 KurrentDBPool.shared 背後、由 KURRENTDB_POOL_URLS 指定的容器，
/// 走 borrow()/withBorrowedClient() 這兩個真正會打 RPC 的入口——跟 KurrentDBPoolTests.swift
/// 裡純 actor 記帳邏輯的測試分開。
///
/// 沒設 KURRENTDB_POOL_URLS 時整個 suite 用 .enabled(if:) 跳過，而不是讓每個
/// 測試各自因為拿不到 client 而記錄失敗——標準的 `swift test` 在沒有額外準備
/// 好多台獨立 KurrentDB 實例的環境下（例如一般開發機、offline CI job）應該
/// 乾淨跳過這個 suite，而不是回傳非 0 的結果。
@Suite(
    "KurrentDBPool Live Tests",
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["KURRENTDB_POOL_URLS"] != nil)
)
struct KurrentDBPoolLiveTests {
    @Test("withBorrowedClient 借到一個真的能打 RPC 的 client")
    func testWithBorrowedClientWorks() async throws {
        let members = try await withBorrowedClient { borrowed in
            try await borrowed.client.readCluster()
        }
        #expect(members != nil)
        #expect(members?.isEmpty == false)
    }

    @Test("借用範圍結束後 isGivenBack 讀到 true——這只是 pool 帳本訊號，不代表底層 client 被擋住")
    func testIsGivenBackReflectsPoolBookkeeping() async {
        var capturedBorrowed: BorrowedClient?
        _ = await withBorrowedClient { borrowed in
            capturedBorrowed = borrowed
        }

        guard let borrowed = capturedBorrowed else {
            Issue.record("預期能拿到 BorrowedClient")
            return
        }

        #expect(borrowed.isGivenBack)
    }

    @Test("同時借兩個不同成員，各自寫入的事件不會出現在對方那裡（隔離驗證）")
    func testTwoSimultaneousBorrowsAreIsolated() async throws {
        // 這個測試天生需要至少兩個成員——第二次 borrow() 才有機會拿到跟第一次
        // 不同的那個。只設一個成員時，第二次 borrow() 內部的 acquire() 會因為
        // 池子非空但全忙碌而真的排隊掛起，永遠等不到 first 才會發生的 release()。
        // 先檢查數量、不夠就明確跳過，不要讓整個測試執行卡死在這裡。
        guard await KurrentDBPool.shared.count >= 2 else {
            return
        }

        guard let first = await KurrentDBPool.borrow() else {
            Issue.record("預期能借到第一個")
            return
        }
        guard let second = await KurrentDBPool.borrow() else {
            await first.giveBack()
            Issue.record("預期能借到第二個——池子裡至少要有兩個成員")
            return
        }

        let streamName = "kurrentdb-pool-isolation-\(UUID().uuidString)"
        let events = [EventData(eventType: "PoolIsolationTest", model: ["ok": true])]

        try await first.client.streams(specified: streamName)
            .append(events: events) { $0.expectedRevision = .any }

        var readBackOnFirst: [String] = []
        let responses = try await first.client.streams(specified: streamName).read {
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
            let responses = try await second.client.streams(specified: streamName).read()
            var iterator = responses.makeAsyncIterator()
            _ = try await iterator.next()
        }

        try await first.client.streams(specified: streamName).delete()
        await first.giveBack()
        await second.giveBack()
    }

    @Test("borrow() 在唯一的候選人連不到時嘗試完就回 nil，不會自己把自己鎖死（迴歸測試）")
    func testBorrowDoesNotDeadlockWithSingleDeadCandidate() async {
        // 把 shared 目前所有本來就存在的成員先借光，讓下面新增的壞地址
        // 變成唯一可能被抽到的候選人——這樣才能確定 borrow() 真的會碰到它，
        // 而不是繞過去抽到別的活成員。
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

    @Test("候選人輪替不會讓健康成員被排在前面的壞成員永久卡住（迴歸測試）")
    func testBorrowRotatesPastPersistentlyBadCandidates() async {
        // 借光目前所有本來就存在的成員，讓接下來加的候選人變成唯一可見的。
        var heldLive: [KurrentDBPool.Lease] = []
        while let lease = await KurrentDBPool.shared.tryAcquire() {
            heldLive.append(lease)
        }

        guard let goodSettings = heldLive.first?.settings else {
            Issue.record("需要至少一個活的成員來源設定")
            return
        }

        // 順序很重要：3 個連不到的先插進去，健康的最後才加——修好之前，
        // firstIdleID() 固定依插入順序掃描，healthy 成員永遠排在最後面，
        // 而 giveBack() 把壞成員還回去時也不會改變它們的位置，所以每次
        // borrow() 都會重測同樣 3 個壞成員，好成員永遠輪不到。
        var deadIDs: [KurrentDBPool.MemberID] = []
        for _ in 0..<3 {
            deadIDs.append(await KurrentDBPool.shared.add(.remote(.init(host: "127.0.0.1", port: 1), secure: false)))
        }
        let goodID = await KurrentDBPool.shared.add(goodSettings)

        // 4 個候選人、maxAttempts=3，最多兩次呼叫（6 次嘗試）保證輪過一整輪。
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
