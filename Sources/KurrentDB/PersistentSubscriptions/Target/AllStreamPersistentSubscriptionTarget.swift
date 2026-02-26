//
//  AllStreamPersistentSubscriptionTarget.swift
//  KurrentDB
//

/// A target that identifies a persistent subscription on the `$all` stream.
public struct AllStreamPersistentSubscriptionTarget: PersistentSubscriptionTarget {
    /// The subscription group name.
    public private(set) var group: String

    public init(group: String) {
        self.group = group
    }
}

extension PersistentSubscriptionTarget where Self == AllStreamPersistentSubscriptionTarget {
    /// Creates a target for the `$all` stream and subscription group.
    public static func allStreams(group: String) -> AllStreamPersistentSubscriptionTarget {
        .init(group: group)
    }
}
