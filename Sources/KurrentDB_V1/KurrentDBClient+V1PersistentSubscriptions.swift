//
//  KurrentDBClient+V1PersistentSubscriptions.swift
//  swift-kurrentdb
//
//  Compatibility layer — convenience methods for persistent subscriptions.
//  Prefer the target-based API: client.persistentSubscriptions(of:), client.persistentSubscriptions(stream:group:)
//

import KurrentDB

@available(*, deprecated, message: "Use the target-based API instead: client.persistentSubscriptions(of:), client.persistentSubscriptions(stream:group:), client.allPersistentSubscriptions")
extension KurrentDBClient {

    // MARK: - StreamIdentifier-based overloads

    /// Creates a persistent subscription group for a specific stream.
    public func createPersistentSubscription(stream streamIdentifier: StreamIdentifier, groupName: String, configure: @Sendable (PersistentSubscriptionsCreateOptions) -> PersistentSubscriptionsCreateOptions = { $0 }) async throws(KurrentError) {
        try await streams(of: .specified(streamIdentifier))
            .persistentSubscriptions(group: groupName)
            .create {
                $0 = .init(from: configure(.init()))
            }
    }

    /// Creates a persistent subscription group for the `$all` stream.
    public func createPersistentSubscriptionToAllStream(groupName: String, configure: @Sendable (PersistentSubscriptionsAllStreamCreateOptions) -> PersistentSubscriptionsAllStreamCreateOptions = { $0 }) async throws(KurrentError) {
        try await streams(of: .all)
            .persistentSubscriptions(group: groupName)
            .create {
                $0 = .init(from: configure(.init()))
            }
    }

    /// Updates configuration for an existing persistent subscription group.
    public func updatePersistentSubscription(stream streamIdentifier: StreamIdentifier, groupName: String, configure: @Sendable (PersistentSubscriptionsUpdateOptions) -> PersistentSubscriptionsUpdateOptions = { $0 }) async throws(KurrentError) {
        try await streams(of: .specified(streamIdentifier))
            .persistentSubscriptions(group: groupName)
            .update {
                $0 = .init(from: configure(.init()))
            }
    }

    /// Updates configuration for a persistent subscription group on the `$all` stream.
    public func updatePersistentSubscriptionToAllStream(groupName: String, configure: @Sendable (PersistentSubscriptionsAllStreamUpdateOptions) -> PersistentSubscriptionsAllStreamUpdateOptions = { $0 }) async throws(KurrentError) {
        try await streams(of: .all)
            .persistentSubscriptions(group: groupName)
            .update {
                $0 = .init(from: configure(.init()))
            }
    }

    /// Subscribes a consumer to a persistent subscription group.
    public func subscribePersistentSubscription(stream streamIdentifier: StreamIdentifier, groupName: String, configure: @Sendable (PersistentSubscriptionsReadOptions) -> PersistentSubscriptionsReadOptions = { $0 }) async throws(KurrentError) -> PersistentSubscriptions<SpecifiedPersistentSubscriptionTarget>.Subscription<PersistentSubscription.EventResult> {
        let stream = streams(of: .specified(streamIdentifier))
        return try await stream.persistentSubscriptions(group: groupName).subscribe {
            $0 = .init(from: configure(.init()))
        }
    }

    /// Subscribes a consumer to a persistent subscription group on the `$all` stream.
    public func subscribePersistentSubscriptionToAllStreams(groupName: String, configure: @Sendable (PersistentSubscriptionsAllStreamReadOptions) -> PersistentSubscriptionsAllStreamReadOptions = { $0 }) async throws(KurrentError) -> PersistentSubscriptions<AllStreamPersistentSubscriptionTarget>.Subscription<PersistentSubscription.EventResult> {
        let stream = streams(of: .all)
        return try await stream.persistentSubscriptions(group: groupName).subscribe {
            $0 = .init(from: configure(.init()))
        }
    }

    /// Deletes a persistent subscription group.
    public func deletePersistentSubscription(stream streamIdentifier: StreamIdentifier, groupName: String) async throws(KurrentError) {
        try await streams(of: .specified(streamIdentifier))
            .persistentSubscriptions(group: groupName)
            .delete()
    }

    /// Deletes a persistent subscription group from the `$all` stream.
    public func deletePersistentSubscriptionToAllStream(groupName: String) async throws(KurrentError) {
        try await streams(of: .all)
            .persistentSubscriptions(group: groupName)
            .delete()
    }

    /// Lists all persistent subscription groups for a specific stream.
    public func listPersistentSubscriptions(stream streamIdentifier: StreamIdentifier) async throws(KurrentError) -> [PersistentSubscription.SubscriptionInfo] {
        try await persistentSubscriptions(of: .filter(stream: streamIdentifier.name)).list()
    }

    /// Lists all persistent subscription groups for the `$all` stream.
    public func listPersistentSubscriptionsToAllStream() async throws(KurrentError) -> [PersistentSubscription.SubscriptionInfo] {
        try await persistentSubscriptions(of: .all).list()
    }

    /// Lists all persistent subscription groups across all streams.
    public func listAllPersistentSubscription() async throws(KurrentError) -> [PersistentSubscription.SubscriptionInfo] {
        try await persistentSubscriptions(of: .all).list()
    }

    /// Restarts the entire persistent subscription subsystem across the cluster.
    public func restartPersistentSubscriptionSubsystem() async throws(KurrentError) {
        try await persistentSubscriptions(of: .all).restartSubsystem()
    }

    // MARK: - String-based convenience overloads

    /// Creates a persistent subscription group for a stream identified by name.
    public func createPersistentSubscription(stream streamName: String, groupName: String, configure: @Sendable (PersistentSubscriptionsCreateOptions) -> PersistentSubscriptionsCreateOptions = { $0 }) async throws(KurrentError) {
        try await streams(of: .specified(streamName))
            .persistentSubscriptions(group: groupName)
            .create {
                $0 = .init(from: configure(.init()))
            }
    }

    /// Updates configuration for a persistent subscription group on a stream identified by name.
    public func updatePersistentSubscription(stream streamName: String, groupName: String, configure: @Sendable (PersistentSubscriptionsUpdateOptions) -> PersistentSubscriptionsUpdateOptions = { $0 }) async throws(KurrentError) {
        try await streams(of: .specified(streamName))
            .persistentSubscriptions(group: groupName)
            .update {
                $0 = .init(from: configure(.init()))
            }
    }

    /// Subscribes to a persistent subscription group on a stream identified by name.
    public func subscribePersistentSubscription(stream streamName: String, groupName: String, configure: @Sendable (PersistentSubscriptionsReadOptions) -> PersistentSubscriptionsReadOptions = { $0 }) async throws(KurrentError) -> PersistentSubscriptions<SpecifiedPersistentSubscriptionTarget>.Subscription<PersistentSubscription.EventResult> {
        let stream = streams(of: .specified(streamName))
        return try await stream.persistentSubscriptions(group: groupName).subscribe {
            $0 = .init(from: configure(.init()))
        }
    }

    /// Deletes a persistent subscription group from a stream identified by name.
    public func deletePersistentSubscription(stream streamName: String, groupName: String) async throws(KurrentError) {
        try await streams(of: .specified(streamName))
            .persistentSubscriptions(group: groupName)
            .delete()
    }

    /// Lists persistent subscription groups on a stream identified by name.
    public func listPersistentSubscriptions(stream streamName: String) async throws(KurrentError) -> [PersistentSubscription.SubscriptionInfo] {
        try await persistentSubscriptions(of: .all).list()
    }
}
