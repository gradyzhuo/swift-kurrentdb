import Foundation
import KurrentDB

package actor KurrentDBPool {
    package static let shared = KurrentDBPool()

    package struct MemberID: Hashable, Sendable {
        fileprivate let raw = UUID()
    }

    package struct Lease: Sendable {
        package let id: MemberID
        package let settings: ClientSettings

        package func giveBack() async {
            await KurrentDBPool.shared.release(self)
        }
    }

    private struct Member {
        var settings: ClientSettings
        var isBusy = false
        var pendingRemoval = false
    }

    /// 排隊等候的 acquire()。id 讓取消處理能精確地把「這一個」從佇列裡拔掉，
    /// 而不是猜哪一個 continuation 對應哪個呼叫端。
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Lease?, Never>
    }

    private var members: [MemberID: Member] = [:]
    private var order: [MemberID] = []
    private var waiters: [Waiter] = []

    package init(settings: [ClientSettings] = KurrentDBPool.settingsFromEnv()) {
        for settings in settings {
            let id = MemberID()
            members[id] = Member(settings: settings)
            order.append(id)
        }
    }

    @discardableResult
    package func add(_ settings: ClientSettings) -> MemberID {
        let id = insert(settings)
        dispatchNextWaiterIfPossible()
        return id
    }

    /// 忙碌中的成員先標記待移除，等它 release 時才真的拿掉——
    /// 不強行打斷正在使用它的租約持有者。
    package func remove(_ id: MemberID) {
        guard var member = members[id] else { return }
        guard member.isBusy else {
            members.removeValue(forKey: id)
            order.removeAll { $0 == id }
            return
        }
        member.pendingRemoval = true
        members[id] = member
    }

    /// 池子非空但全忙碌時會排隊掛起，直到有人 release()/add()。
    /// 支援取消：Task 被取消時會從佇列移除並回傳 nil，不會讓一個沒人記得的
    /// continuation 永遠卡在佇列裡、悄悄吃掉一個租約。
    package func acquire() async -> Lease? {
        guard !members.isEmpty else { return nil }
        if let id = firstIdleID() { return lease(marking: id) }

        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (k: CheckedContinuation<Lease?, Never>) in
                waiters.append(Waiter(id: waiterID, continuation: k))
            }
        } onCancel: {
            Task { await self.cancelWaiter(waiterID) }
        }
    }

    /// 不排隊的版本——沒有任何成員閒置就立刻回 nil，不會掛起等待。
    /// borrow() 用這個在同一次呼叫裡換下一個候選人：如果目前真的沒有其他
    /// 候選人可換，就該立刻放棄，而不是等一個永遠不會發生的 release()。
    package func tryAcquire() -> Lease? {
        guard let id = firstIdleID() else { return nil }
        return lease(marking: id)
    }

    package func release(_ lease: Lease) {
        guard var member = members[lease.id] else { return }
        if member.pendingRemoval {
            members.removeValue(forKey: lease.id)
            order.removeAll { $0 == lease.id }
            if members.isEmpty {
                // 池子因為移除最後一個成員而變空——跟一個全新的 acquire() 遇到
                // 空池一樣，所有還在排隊的 waiter 都該立刻拿到 nil，而不是繼續
                // 卡著等一個不可能發生的 release()。
                let pending = waiters
                waiters = []
                for waiter in pending { waiter.continuation.resume(returning: nil) }
                return
            }
        } else {
            member.isBusy = false
            members[lease.id] = member
        }
        dispatchNextWaiterIfPossible()
    }

    private func insert(_ settings: ClientSettings) -> MemberID {
        let id = MemberID()
        members[id] = Member(settings: settings)
        order.append(id)
        return id
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(returning: nil)
    }

    private func dispatchNextWaiterIfPossible() {
        guard !waiters.isEmpty, let id = firstIdleID() else { return }
        waiters.removeFirst().continuation.resume(returning: lease(marking: id))
    }

    private func lease(marking id: MemberID) -> Lease {
        members[id]!.isBusy = true
        return Lease(id: id, settings: members[id]!.settings)
    }

    private func firstIdleID() -> MemberID? {
        order.first { members[$0].map { !$0.isBusy && !$0.pendingRemoval } ?? false }
    }
}
