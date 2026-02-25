//
//  KurrentDBClient+PersistentSubscriptions.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2025/5/23.
//

// MARK: - Persistent Subscription Factory Methods

extension KurrentDBClient {
    /// Returns a persistent subscriptions interface for cluster-wide operations.
    public var allPersistentSubscriptions: PersistentSubscriptions<PersistentSubscription.All> {
        .init(target: .all, selector: selector, callOptions: defaultCallOptions)
    }

    /// Creates a persistent subscriptions interface for a specific target type.
    public func persistentSubscriptions<Target: PersistentSubscriptionTarget>(of target: Target) -> PersistentSubscriptions<Target> {
        .init(target: target, selector: selector, callOptions: defaultCallOptions)
    }

    /// Creates a persistent subscriptions interface for a specific stream and group.
    public func persistentSubscriptions(stream: String, group: String) -> PersistentSubscriptions<PersistentSubscription.Specified> {
        .init(target: .specified(stream: stream, group: group), selector: selector, callOptions: defaultCallOptions)
    }

    /// Creates a persistent subscriptions interface filtered by group name across all streams.
    public func persistentSubscriptions(filterGroup groupName: String) -> PersistentSubscriptions<PersistentSubscription.AllStream> {
        .init(target: .allStreams(group: groupName), selector: selector, callOptions: defaultCallOptions)
    }

    /// Creates a persistent subscriptions interface filtered by stream name.
    public func persistentSubscriptions(filterStream stream: String) -> PersistentSubscriptions<PersistentSubscription.FilterStream> {
        .init(target: .filter(stream: stream), selector: selector, callOptions: defaultCallOptions)
    }
}
