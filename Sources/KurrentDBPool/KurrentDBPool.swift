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

    private var members: [MemberID: Member] = [:]
    private var order: [MemberID] = []
    private var waiters: [CheckedContinuation<Lease, Never>] = []

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

    package func acquire() async -> Lease? {
        guard !members.isEmpty else { return nil }
        if let id = firstIdleID() { return lease(marking: id) }
        return await withCheckedContinuation { (k: CheckedContinuation<Lease, Never>) in
            waiters.append(k)
        }
    }

    package func release(_ lease: Lease) {
        guard var member = members[lease.id] else { return }
        if member.pendingRemoval {
            members.removeValue(forKey: lease.id)
            order.removeAll { $0 == lease.id }
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

    private func dispatchNextWaiterIfPossible() {
        guard !waiters.isEmpty, let id = firstIdleID() else { return }
        waiters.removeFirst().resume(returning: lease(marking: id))
    }

    private func lease(marking id: MemberID) -> Lease {
        members[id]!.isBusy = true
        return Lease(id: id, settings: members[id]!.settings)
    }

    private func firstIdleID() -> MemberID? {
        order.first { members[$0].map { !$0.isBusy && !$0.pendingRemoval } ?? false }
    }
}
