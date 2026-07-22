//
//  SubscriptionRealPathLifecycleTests.swift
//  swift-kurrentdb
//
//  這個 suite 只驗證一件事:透過真正的 `PersistentSubscriptions.subscribe()`(亦即
//  `Read.send`)拿到 handle 後,若從未存取 `.events` 就直接丟棄它,連線仍會被關閉。
//
//  `Tests/PersistentSubscriptionsTests/SubscriptionLifecycleTests.swift` 裡的等價測試
//  是直接建構 `Subscription`,略過了 `Read.send` 裡會強持有該物件的 RPC task,因此
//  抓不到這一類 retain cycle——這正是該缺陷過去能上線的原因。本測試改走真正的
//  `subscribe()` 路徑來補這個洞。
//
//  獨立成一個 suite,方便在 PersistentSubscriptionAdvancedTests 于本機環境間歇性
//  卡住時,仍能單獨執行本測試做隔離驗證:
//  `swift test --filter SubscriptionRealPathLifecycleTests ...`
//

import Foundation
@testable import KurrentDB
import Testing

@Suite("Persistent Subscription 真實路徑生命週期契約", .serialized, .timeLimit(.minutes(2)))
struct SubscriptionRealPathLifecycleTests: Sendable {
    let settings: ClientSettings
    let groupName: String

    init() {
        settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .certificate(source: .crtInBundle("ca", inBundle: .module)!)
        groupName = "test-ps-realpath-\(UUID().uuidString)"
    }

    /// `withCheckedContinuation` 的回傳型別:標明 teardown 訊號實際上是怎麼收到的,
    /// 讓斷言可以區分「訂閱失敗」與「teardown 真的發生」,而不是靠猜測。
    private enum Outcome: Sendable {
        case tornDown
        case subscribeFailed(String)
    }

    @Test("透過真實的 subscribe() 拿到 handle、從未存取 events 就丟棄,連線仍會關閉")
    func droppingRealSubscriptionWithoutIteratingTearsDownConnection() async throws {
        let streamName = UUID().uuidString
        let client = KurrentDBClient(settings: settings)
        let ps = client.persistentSubscriptions(stream: streamName, group: groupName)
        try await ps.create()

        // 等待實際的 teardown 訊號,而非猜測排程時機或靠計時器判斷。
        //
        // 訊號來源:`Subscription.init` 佈署的 handler,由 `source.continuation`
        // 的 `onTermination` 觸發。在本測試情境下,唯一能讓它觸發的路徑是「handle
        // 被釋放」——我們從未呼叫 `subscription.events`(不會有消費者跳出迴圈),
        // 也不曾送出任何 `.finish` 狀態,伺服器端這個持久訂閱本身也不會主動結束
        // 一個正常在線的連線。因此 teardown 訊號能收到,就直接證明了 dealloc 鏈
        // 被走過。
        //
        // 訊號抵達時,`tracker.callFinishActionOnce` 已經依註冊順序執行完
        // `Read.send` 內部安裝的清理 action(呼叫 completion、取消 RPC task,
        // 進而取消 `perform(node:)` 裡的 `connectionTask` 並呼叫
        // `client.beginGracefulShutdown()`),我們在此註冊的觀察者只會接在其後——
        // 這是 `SubscriptionTracker.update(action:)` 疊加多個觀察者的行為保證的。
        //
        // 若 teardown 從未發生,測試會停在此處,由 suite 的 `.timeLimit` 攔截。
        // 斷言本身不含任何時間值,時間界限只存在於維運層。
        let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<Outcome, Never>) in
            Task {
                do {
                    let subscription = try await ps.subscribe()
                    // 疊加一個觀察者;不會覆蓋 `Read.send` 已裝好的內部清理 action。
                    subscription.onFinish { _ in continuation.resume(returning: .tornDown) }
                    // 刻意不存取 subscription.events,也不再持有 subscription——
                    // 離開這個 do 區塊,就是外部唯一強參照消失的時刻。
                } catch {
                    continuation.resume(returning: .subscribeFailed("\(error)"))
                }
            }
        }

        switch outcome {
        case .tornDown:
            break
        case let .subscribeFailed(message):
            Issue.record("ps.subscribe() 失敗,無法驗證 teardown:\(message)")
        }

        // 注意:本測試從未對 streamName append 任何事件(建立 persistent
        // subscription 不要求目標串流已存在),因此這裡只需清掉 subscription 本身。
        try await ps.delete()
    }
}
