//
//  SpecifiedPersistentSubscriptionTarget.swift
//  KurrentDB
//

import Foundation

/// Target scoping a persistent subscription to a specific named stream.
public struct SpecifiedPersistentSubscriptionTarget: PersistentSubscriptionTarget {
    /// Identifier of the stream this subscription reads from.
    public private(set) var identifier: StreamIdentifier

    /// Consumer group name for this subscription.
    public private(set) var group: String

    public init(identifier: StreamIdentifier, group: String) {
        self.identifier = identifier
        self.group = group
    }
}

extension PersistentSubscriptionTarget where Self == SpecifiedPersistentSubscriptionTarget {
    /// Creates a target for the named stream and consumer group.
    public static func specified(stream name: String, encoding: String.Encoding = .utf8, group: String) -> SpecifiedPersistentSubscriptionTarget {
        .init(identifier: .init(name: name, encoding: encoding), group: group)
    }
}
