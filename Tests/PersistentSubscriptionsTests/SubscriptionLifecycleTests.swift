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

    @Test("T1:從未存取 events 就丟棄,仍會觸發 teardown")
    func droppingWithoutIteratingTearsDown() async throws {
        // 等待實際的 teardown 訊號,而非猜測排程時機。
        // `deinit` 因 ARC 在 closure 結束時確定性觸發,但它驅動 `onTermination`
        // 的時機是 AsyncStream 的實作細節 —— 故等待訊號而非 Task.yield()。
        //
        // 若 teardown 從未發生,測試會停在此處,由 suite 的 `.timeLimit` 攔截。
        // 這正是設計意圖:斷言本身不含任何時間值,時間界限只存在於維運層。
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let writer = Sub.Writer()
            let sub = Sub(writer: writer)
            sub.onFinish { _ in continuation.resume() }
            // 刻意不存取 sub.events;離開此 closure 後 sub 立即被釋放。
            // 沒有 bridge task 持有它,故釋放是確定的。
        }
        // 能執行到此行,即代表 teardown 確實被觸發 —— 這就是斷言。
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
