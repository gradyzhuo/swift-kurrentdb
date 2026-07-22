//
//  PersistentSubscriptions.WeakSubscriptionRef.swift
//  KurrentDB
//

import Synchronization

extension PersistentSubscriptions {
    /// 對 ``Subscription`` 的弱參照,本身可安全地被強捕獲。
    ///
    /// Read usecase 的 RPC task 需要在收到訊息時通知 subscription,但**不得**強持有它 ——
    /// 否則會與 `tracker` 所存的 finish action 形成保留循環
    /// (`subscription → tracker → finish action → task → subscription`),
    /// 使 subscription 永不釋放,「丟棄 handle 即關閉連線」因而無法成立。
    ///
    /// 無法直接在 `Task { [weak subscription] in ... }` 內於巢狀的 `@Sendable` closure
    /// 引用該弱綁定 —— Swift 6 會報
    /// `reference to captured var in concurrently-executing code`。
    /// 故改以本型別承載弱參照:task 與其巢狀 closure 強捕獲本物件(僅一個鎖與一個弱指標),
    /// 而目標 subscription 仍只被弱持有。
    package final class WeakSubscriptionRef<EventResult: SubscriptionEventResult>: Sendable {
        private struct Holder {
            weak var value: Subscription<EventResult>?
        }

        private let storage: Mutex<Holder>

        package init(_ subscription: Subscription<EventResult>) {
            storage = Mutex(Holder(value: subscription))
        }

        /// 目前的 subscription;若已釋放則為 `nil`,代表無人再監聽,呼叫端應停止傳送。
        package var value: Subscription<EventResult>? {
            storage.withLock { $0.value }
        }
    }
}
