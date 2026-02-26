//
//  AllPersistentSubscriptionTarget.swift
//  KurrentDB
//

/// A target for cluster-wide persistent subscription operations (list all, restart subsystem).
public struct AllPersistentSubscriptionTarget: PersistentSubscriptionTarget {}

extension PersistentSubscriptionTarget where Self == AllPersistentSubscriptionTarget {
    /// Returns the target representing all persistent subscriptions across the cluster.
    public static var all: AllPersistentSubscriptionTarget {
        .init()
    }
}
