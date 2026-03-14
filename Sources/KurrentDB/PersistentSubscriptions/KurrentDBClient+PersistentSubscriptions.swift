//
//  KurrentDBClient+PersistentSubscriptions.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2025/5/23.
//

// MARK: - Persistent Subscription Factory Methods

extension KurrentDBClient {
    /// Accesses persistent subscriptions for cluster-wide operations (list, restart subsystem).
    ///
    /// ```swift
    /// let allSubs = try await client.allPersistentSubscriptions.list()
    /// ```
    public var allPersistentSubscriptions: PersistentSubscriptions<AllPersistentSubscriptionTarget> {
        .init(target: .all, selector: selector, callOptions: defaultCallOptions)
    }

    /// Creates a persistent subscriptions interface for a specific target type.
    ///
    /// - Parameter target: The subscription target defining the scope.
    /// - Returns: A configured ``PersistentSubscriptions`` instance.
    public func persistentSubscriptions<Target: PersistentSubscriptionTarget>(of target: Target) -> PersistentSubscriptions<Target> {
        .init(target: target, selector: selector, callOptions: defaultCallOptions)
    }

    /// Creates a persistent subscriptions interface for a specific stream and consumer group.
    ///
    /// ```swift
    /// let sub = client.persistentSubscriptions(stream: "orders", group: "order-processor")
    /// try await sub.create()
    /// let subscription = try await sub.subscribe()
    /// ```
    ///
    /// - Parameters:
    ///   - stream: The stream name to subscribe to.
    ///   - group: The consumer group name.
    public func persistentSubscriptions(stream: String, group: String) -> PersistentSubscriptions<SpecifiedPersistentSubscriptionTarget> {
        .init(target: .specified(stream: stream, group: group), selector: selector, callOptions: defaultCallOptions)
    }

    /// Lists persistent subscriptions filtered by consumer group name across all streams.
    ///
    /// - Parameter groupName: The consumer group name to filter by.
    public func persistentSubscriptions(filterGroup groupName: String) -> PersistentSubscriptions<AllStreamPersistentSubscriptionTarget> {
        .init(target: .allStreams(group: groupName), selector: selector, callOptions: defaultCallOptions)
    }

    /// Lists persistent subscriptions filtered by stream name.
    ///
    /// - Parameter stream: The stream name to filter by.
    public func persistentSubscriptions(filterStream stream: String) -> PersistentSubscriptions<FilterStreamPersistentSubscriptionTarget> {
        .init(target: .filter(stream: stream), selector: selector, callOptions: defaultCallOptions)
    }
}
