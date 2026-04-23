//
//  FilterStreamPersistentSubscriptionTarget.swift
//  KurrentDB
//

/// Target that filters persistent subscription listings to a specific stream name.
public struct FilterStreamPersistentSubscriptionTarget: PersistentSubscriptionTarget {
    let stream: String

    public init(stream: String) {
        self.stream = stream
    }
}

extension PersistentSubscriptionTarget where Self == FilterStreamPersistentSubscriptionTarget {
    /// Creates a target that filters subscription listings to the given stream name.
    public static func filter(stream: String) -> FilterStreamPersistentSubscriptionTarget {
        .init(stream: stream)
    }
}
