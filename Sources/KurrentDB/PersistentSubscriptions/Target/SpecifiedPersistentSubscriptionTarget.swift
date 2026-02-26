//
//  SpecifiedPersistentSubscriptionTarget.swift
//  KurrentDB
//

import Foundation

/// A target that identifies a persistent subscription on a specific named stream.
public struct SpecifiedPersistentSubscriptionTarget: PersistentSubscriptionTarget {
    /// The identifier of the stream.
    public private(set) var identifier: StreamIdentifier

    /// The subscription group name.
    public private(set) var group: String

    public init(identifier: StreamIdentifier, group: String) {
        self.identifier = identifier
        self.group = group
    }
}

extension PersistentSubscriptionTarget where Self == SpecifiedPersistentSubscriptionTarget {
    /// Creates a target for a named stream and subscription group.
    public static func specified(stream name: String, encoding: String.Encoding = .utf8, group: String) -> SpecifiedPersistentSubscriptionTarget {
        .init(identifier: .init(name: name, encoding: encoding), group: group)
    }
}
