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

        /// Gives the lease back to the pool that issued it, not to a hard-coded KurrentDBPool.shared.
        /// A lease from acquire() on a custom (non-shared) pool instance goes back to that
        /// instance, instead of quietly going to shared under a MemberID that does not exist there,
        /// which would leave the original pool one member short for good.
        package func giveBack() async {
            await owner.release(self)
        }
    }

    private struct Member {
        var settings: ClientSettings
        var isBusy = false
        var pendingRemoval = false
    }

    /// An acquire() waiting in the queue. The id lets cancellation remove exactly this one from the
    /// queue, without guessing which continuation belongs to which caller.
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Lease?, Never>
    }

    private var members: [MemberID: Member] = [:]
    private var order: [MemberID] = []
    private var waiters: [Waiter] = []

    /// Where firstIdleID() starts scanning order. It moves one place on for every member handed out.
    /// Without it order is fixed, and giveBack() returning a failed candidate does not change its
    /// place in order, so it stays ahead of healthy members inserted later: every borrow() would
    /// test the same bad members again and never reach the healthy ones behind them.
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

    /// A busy member is marked for removal and taken out when it is released, so the holder of
    /// its lease is not interrupted.
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

    /// When the pool has members but all are busy, this queues and suspends until a release() or an add().
    ///
    /// It supports cancellation, in two situations:
    /// 1. The Task was cancelled before acquire() was called. Even the fast path for an idle member
    ///    must not hand one out, so this is refused first; otherwise a lease nobody wants is issued.
    /// 2. It was cancelled after queueing, at the same moment as a dispatch from
    ///    dispatchNextWaiterIfPossible(). If the dispatch wins, the continuation has resumed with
    ///    a real lease, and cancelWaiter() finds nobody in the queue and gives up. Removing from
    ///    the queue cannot close that gap, so Task.isCancelled is checked again after the
    ///    resume: a caller that no longer cares about the call but still received a real lease
    ///    has it given back on the spot, not left to the caller to decide (who would not,
    ///    having been cancelled).
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

    /// The version that does not queue: it returns nil at once when no member is idle.
    /// borrow() uses it to change candidate within one call: when there is no other candidate
    /// left it should give up at once, not wait for a release() that will never come.
    package func tryAcquire() -> Lease? {
        guard let id = firstIdleID() else { return nil }
        return lease(marking: id)
    }

    /// The number of members in the pool now, busy or idle. For callers such as tests to check,
    /// before borrowing, that there are enough members for a scenario, instead of calling acquire()
    /// and waiting, with too few members, for a release() that will never come.
    package var count: Int { members.count }

    package func release(_ lease: Lease) {
        guard var member = members[lease.id] else { return }
        if member.pendingRemoval {
            members.removeValue(forKey: lease.id)
            order.removeAll { $0 == lease.id }
            if members.isEmpty {
                // The pool became empty because its last member was removed. As when a new acquire()
                // meets an empty pool, every waiter still queued gets nil at once, instead of
                // waiting for a release() that cannot happen.
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
