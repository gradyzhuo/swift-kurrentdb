//
//  AllStreamPersistentSubscriptionTarget.swift
//  KurrentDB
//

/// Target scoping a persistent subscription to the `$all` stream.
public struct AllStreamPersistentSubscriptionTarget: PersistentSubscriptionTarget {
    /// Consumer group name for this subscription.
    public private(set) var group: String

    public init(group: String) {
        self.group = group
    }
}

extension PersistentSubscriptionTarget where Self == AllStreamPersistentSubscriptionTarget {
    /// Creates a target for the `$all` stream and the given consumer group.
    public static func allStreams(group: String) -> AllStreamPersistentSubscriptionTarget {
        .init(group: group)
    }
}
