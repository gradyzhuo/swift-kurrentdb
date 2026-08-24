import Foundation
import KurrentDB
import KurrentDBPool
import Testing

/// 這些測試會實際連線到 KurrentDBPool.shared 背後、由 KURRENTDB_POOL_URLS 指定的容器，
/// 走 borrow()/withBorrowedClient() 這兩個真正會打 RPC 的入口——跟 KurrentDBPoolTests.swift
/// 裡純 actor 記帳邏輯的測試分開。
@Suite("KurrentDBPool Live Tests", .serialized)
struct KurrentDBPoolLiveTests {
    @Test("withBorrowedClient 借到一個真的能打 RPC 的 client")
    func testWithBorrowedClientWorks() async throws {
        let members = try await withBorrowedClient { borrowed in
            try await borrowed.client.readCluster()
        }
        #expect(members != nil)
        #expect(members?.isEmpty == false)
    }

    @Test("借用範圍結束後 giveBack() 已經 shutdown，同一個 client 再打 RPC 會失敗")
    func testGiveBackShutsDownClient() async throws {
        var capturedClient: KurrentDBClient?
        _ = await withBorrowedClient { borrowed in
            capturedClient = borrowed.client
        }

        guard let client = capturedClient else {
            Issue.record("預期能拿到 client")
            return
        }

        await #expect(throws: (any Error).self) {
            _ = try await client.readCluster()
        }
    }

    @Test("同時借兩個不同成員，各自寫入的事件不會出現在對方那裡（隔離驗證）")
    func testTwoSimultaneousBorrowsAreIsolated() async throws {
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
}
