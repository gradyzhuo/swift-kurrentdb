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
        private let owner: KurrentDBPool

        fileprivate init(id: MemberID, settings: ClientSettings, owner: KurrentDBPool) {
            self.id = id
            self.settings = settings
            self.owner = owner
        }

        /// 還給發出這個租約的那個 pool——不是寫死的 KurrentDBPool.shared。
        /// 用自訂（非 shared）pool 實例的 acquire() 拿到的 lease 呼叫這個，
        /// 一樣會正確還到原本那個實例，不會悄悄還到 shared 裡一個不存在的
        /// MemberID、讓原本的 pool 永遠少一個可用成員。
        package func giveBack() async {
            await owner.release(self)
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

    /// firstIdleID() 掃描 order 的起點。每次成功配出一個成員就往後移一格——
    /// 沒有這個的話 order 是固定順序,giveBack() 把一個失敗的候選人還回去時
    /// 也不會改變它在 order 裡的位置,於是它永遠排在較晚插入的健康成員前面,
    /// 每次 borrow() 都會重測同一批壞成員,後面的健康成員永遠輪不到。
    private var rotationCursor = 0

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
    ///
    /// 支援取消，處理兩種情況：
    /// 1. 呼叫 acquire() 之前 Task 就已經被取消——連閒置成員的快速路徑都不能
    ///    直接配置，開頭就先擋掉，不然會白白分配一個沒人要的 lease。
    /// 2. 排進佇列之後才被取消，卻剛好跟 dispatchNextWaiterIfPossible() 的
    ///    派送同時發生——如果派送先贏，continuation 已經帶著一個真的 lease
    ///    resume 了，cancelWaiter() 這時候在佇列裡找不到人、直接算了。單靠
    ///    佇列移除擋不住這個空隙，所以 resume 之後另外檢查一次
    ///    Task.isCancelled：如果呼叫端已經不在乎這次呼叫、卻還是分到一個
    ///    真的 lease，就地把它還回去，不要留給呼叫端自己判斷（他們也不會去
    ///    判斷——都取消了）。
    package func acquire() async -> Lease? {
        guard !Task.isCancelled else { return nil }
        guard !members.isEmpty else { return nil }
        if let id = firstIdleID() { return lease(marking: id) }

        let waiterID = UUID()
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { (k: CheckedContinuation<Lease?, Never>) in
                waiters.append(Waiter(id: waiterID, continuation: k))
            }
        } onCancel: {
            Task { await self.cancelWaiter(waiterID) }
        }

        if Task.isCancelled, let lease = result {
            release(lease)
            return nil
        }
        return result
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
        return Lease(id: id, settings: members[id]!.settings, owner: self)
    }

    private func firstIdleID() -> MemberID? {
        guard !order.isEmpty else { return nil }
        let count = order.count
        for offset in 0..<count {
            let index = (rotationCursor + offset) % count
            let id = order[index]
            guard let member = members[id], !member.isBusy, !member.pendingRemoval else { continue }
            rotationCursor = (index + 1) % count
            return id
        }
        return nil
    }
}
