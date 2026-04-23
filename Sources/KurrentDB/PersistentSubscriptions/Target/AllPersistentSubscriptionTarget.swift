//
//  AllPersistentSubscriptionTarget.swift
//  KurrentDB
//

/// Target for cluster-wide persistent subscription operations such as listing all subscriptions.
public struct AllPersistentSubscriptionTarget: PersistentSubscriptionTarget {}

extension PersistentSubscriptionTarget where Self == AllPersistentSubscriptionTarget {
    /// Target representing all persistent subscriptions across the cluster.
    public static var all: AllPersistentSubscriptionTarget {
        .init()
    }
}
