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
    public func createPersistentSubscription(stream streamIdentifier: StreamIdentifier, groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Create.Options) -> PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Create.Options = { $0 }) async throws(KurrentError) {
        let options = configure(.init())
        try await streams(of: .specified(streamIdentifier))
            .persistentSubscriptions(group: groupName)
            .create(options: options)
    }

    /// Creates a persistent subscription group for the `$all` stream.
    public func createPersistentSubscriptionToAllStream(groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.AllStream>.AllStream.Create.Options) -> PersistentSubscriptions<PersistentSubscription.AllStream>.AllStream.Create.Options = { $0 }) async throws(KurrentError) {
        let options = configure(.init())
        try await streams(of: .all)
            .persistentSubscriptions(group: groupName)
            .create(options: options)
    }

    /// Updates configuration for an existing persistent subscription group.
    public func updatePersistentSubscription(stream streamIdentifier: StreamIdentifier, groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Update.Options) -> PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Update.Options = { $0 }) async throws(KurrentError) {
        let options = configure(.init())
        try await streams(of: .specified(streamIdentifier))
            .persistentSubscriptions(group: groupName)
            .update(options: options)
    }

    /// Updates configuration for a persistent subscription group on the `$all` stream.
    public func updatePersistentSubscriptionToAllStream(groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.AllStream>.AllStream.Update.Options) -> PersistentSubscriptions<PersistentSubscription.AllStream>.AllStream.Update.Options = { $0 }) async throws(KurrentError) {
        let options = configure(.init())
        try await streams(of: .all)
            .persistentSubscriptions(group: groupName)
            .update(options: options)
    }

    /// Subscribes a consumer to a persistent subscription group.
    public func subscribePersistentSubscription(stream streamIdentifier: StreamIdentifier, groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Read.Options) -> PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Read.Options = { $0 }) async throws(KurrentError) -> PersistentSubscriptions<PersistentSubscription.Specified>.Subscription {
        let options = configure(.init())
        let stream = streams(of: .specified(streamIdentifier))
        return try await stream.persistentSubscriptions(group: groupName).subscribe(options: options)
    }

    /// Subscribes a consumer to a persistent subscription group on the `$all` stream.
    public func subscribePersistentSubscriptionToAllStreams(groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.AllStream>.AllStream.Read.Options) -> PersistentSubscriptions<PersistentSubscription.AllStream>.AllStream.Read.Options = { $0 }) async throws(KurrentError) -> PersistentSubscriptions<PersistentSubscription.AllStream>.Subscription {
        let options = configure(.init())
        let stream = streams(of: .all)
        return try await stream.persistentSubscriptions(group: groupName).subscribe(options: options)
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
    public func createPersistentSubscription(stream streamName: String, groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Create.Options) -> PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Create.Options = { $0 }) async throws(KurrentError) {
        let options = configure(.init())
        try await streams(of: .specified(streamName))
            .persistentSubscriptions(group: groupName)
            .create(options: options)
    }

    /// Updates configuration for a persistent subscription group on a stream identified by name.
    public func updatePersistentSubscription(stream streamName: String, groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Update.Options) -> PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Update.Options = { $0 }) async throws(KurrentError) {
        let options = configure(.init())
        try await streams(of: .specified(streamName))
            .persistentSubscriptions(group: groupName)
            .update(options: options)
    }

    /// Subscribes to a persistent subscription group on a stream identified by name.
    public func subscribePersistentSubscription(stream streamName: String, groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Read.Options) -> PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Read.Options = { $0 }) async throws(KurrentError) -> PersistentSubscriptions<PersistentSubscription.Specified>.Subscription {
        let options = configure(.init())
        let stream = streams(of: .specified(streamName))
        return try await stream.persistentSubscriptions(group: groupName).subscribe(options: options)
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
