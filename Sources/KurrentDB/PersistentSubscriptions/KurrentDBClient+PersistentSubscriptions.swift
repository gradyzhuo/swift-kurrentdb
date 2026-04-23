//
//  KurrentDBClient+PersistentSubscriptions.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2025/5/23.
//

// MARK: - Persistent Subscription Factory Methods

extension KurrentDBClient {
    /// Provides access to cluster-wide persistent subscription operations such as listing all subscriptions.
    ///
    /// - Returns: A `PersistentSubscriptions` instance scoped to all subscriptions.
    public var allPersistentSubscriptions: PersistentSubscriptions<AllPersistentSubscriptionTarget> {
        .init(target: .all, selector: selector, callOptions: defaultCallOptions)
    }

    /// Returns a `PersistentSubscriptions` instance scoped to the given target.
    ///
    /// - Parameter target: The target that defines the subscription scope.
    /// - Returns: A `PersistentSubscriptions` instance for the specified target.
    public func persistentSubscriptions<Target: PersistentSubscriptionTarget>(of target: Target) -> PersistentSubscriptions<Target> {
        .init(target: target, selector: selector, callOptions: defaultCallOptions)
    }

    /// Returns a `PersistentSubscriptions` instance scoped to a specific stream and consumer group.
    ///
    /// - Parameters:
    ///   - stream: Name of the stream to subscribe to.
    ///   - group: Consumer group name for the subscription.
    /// - Returns: A `PersistentSubscriptions` instance for the named stream and group.
    public func persistentSubscriptions(stream: String, group: String) -> PersistentSubscriptions<SpecifiedPersistentSubscriptionTarget> {
        .init(target: .specified(stream: stream, group: group), selector: selector, callOptions: defaultCallOptions)
    }

    /// Returns a `PersistentSubscriptions` instance that lists subscriptions for the given consumer group on all streams.
    ///
    /// - Parameter groupName: Consumer group name to filter by.
    /// - Returns: A `PersistentSubscriptions` instance scoped to the `$all`-stream group.
    public func persistentSubscriptions(filterGroup groupName: String) -> PersistentSubscriptions<AllStreamPersistentSubscriptionTarget> {
        .init(target: .allStreams(group: groupName), selector: selector, callOptions: defaultCallOptions)
    }

    /// Returns a `PersistentSubscriptions` instance that lists subscriptions filtered to a specific stream.
    ///
    /// - Parameter stream: Stream name to filter by.
    /// - Returns: A `PersistentSubscriptions` instance scoped to the given stream filter.
    public func persistentSubscriptions(filterStream stream: String) -> PersistentSubscriptions<FilterStreamPersistentSubscriptionTarget> {
        .init(target: .filter(stream: stream), selector: selector, callOptions: defaultCallOptions)
    }
}
