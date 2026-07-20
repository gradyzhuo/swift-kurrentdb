//
//  SubscriptionLifecycleTests.swift
//  swift-kurrentdb
//

import Testing
import Synchronization
@testable import KurrentDB

@Suite("Subscription 生命週期契約", .serialized, .timeLimit(.minutes(1)))
struct SubscriptionLifecycleTests {

    typealias Sub = PersistentSubscriptions<SpecifiedPersistentSubscriptionTarget>.Subscription<PersistentSubscription.EventResult>

    /// `Mutex` 本身是 noncopyable,無法直接放進 tuple 回傳,
    /// 因此用一個 class 包裝,提供 teardown 次數的執行緒安全計數。
    private final class TeardownCounter: Sendable {
        private let mutex = Mutex<Int>(0)

        var count: Int {
            mutex.withLock { $0 }
        }

        func increment() {
            mutex.withLock { $0 += 1 }
        }
    }

    /// 建立一個 subscription 並記錄 teardown 是否被呼叫。
    private func makeSubscription() -> (sub: Sub, tornDown: TeardownCounter) {
        let writer = Sub.Writer()
        let sub = Sub(writer: writer)
        let counter = TeardownCounter()
        sub.onFinish { _ in counter.increment() }
        return (sub, counter)
    }

    @Test("T3:RPC 拋錯時 events 拋出且 teardown 執行")
    func rpcErrorTerminatesAndTearsDown() async throws {
        let (sub, tornDown) = makeSubscription()
        // 先同步驅動失敗,再 await —— 不使用任何計時
        sub.send(state: .finish(throwing: KurrentError.connectionClosed))

        await #expect(throws: (any Error).self) {
            for try await _ in sub.events { }
        }
        #expect(tornDown.count == 1)
    }

    @Test("T2:迭代後跳出迴圈會觸發 teardown")
    func breakingOutTearsDown() async throws {
        let (sub, tornDown) = makeSubscription()
        sub.send(state: .finish())   // 正常結束

        for try await _ in sub.events { break }
        #expect(tornDown.count == 1)
    }

    @Test("T5:teardown 重複觸發只執行一次")
    func teardownIsIdempotent() async throws {
        let (sub, tornDown) = makeSubscription()
        sub.send(state: .finish())
        for try await _ in sub.events { }
        sub.send(state: .finish())   // 再次終止

        #expect(tornDown.count == 1)
    }
}
