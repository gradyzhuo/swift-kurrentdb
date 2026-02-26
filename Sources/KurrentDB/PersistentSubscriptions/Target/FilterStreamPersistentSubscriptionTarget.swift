//
//  FilterStreamPersistentSubscriptionTarget.swift
//  KurrentDB
//

/// A target used to list or filter subscriptions by stream name.
public struct FilterStreamPersistentSubscriptionTarget: PersistentSubscriptionTarget {
    let stream: String

    public init(stream: String) {
        self.stream = stream
    }
}

extension PersistentSubscriptionTarget where Self == FilterStreamPersistentSubscriptionTarget {
    /// Creates a filter target scoped to a specific stream name.
    public static func filter(stream: String) -> FilterStreamPersistentSubscriptionTarget {
        .init(stream: stream)
    }
}
