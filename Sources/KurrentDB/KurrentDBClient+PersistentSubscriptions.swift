//
//  KurrentDBClient+PersistentSubscriptions.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/5/23.
//

extension KurrentDBClient {
    /// Creates a persistent subscription for a specified stream.
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the stream to subscribe to.
    ///   - groupName: The name of the subscription group.
    ///   - configure: A closure to configure the creation options.
    /// - Throws: An error if the subscription creation fails.
    public func createPersistentSubscription(stream streamIdentifier: StreamIdentifier, groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Create.Options) -> PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Create.Options = { $0 }) async throws {
        let options = configure(.init())
        try await streams(of: .specified(streamIdentifier))
            .persistentSubscriptions(group: groupName)
            .create(options: options)
    }

    /// Creates a persistent subscription for the all-stream.
    ///
    /// - Parameters:
    ///   - groupName: The name of the subscription group.
    ///   - configure: A closure to configure the creation options.
    /// - Throws: An error if the subscription creation fails.
    public func createPersistentSubscriptionToAllStream(groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.AllStream>.AllStream.Create.Options) -> PersistentSubscriptions<PersistentSubscription.AllStream>.AllStream.Create.Options = { $0 }) async throws {
        let options = configure(.init())
        try await streams(of: .all)
            .persistentSubscriptions(group: groupName)
            .create(options: options)
    }

    /// Updates an existing persistent subscription for a specified stream.
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the stream.
    ///   - groupName: The name of the subscription group.
    ///   - configure: A closure to configure the update options.
    /// - Throws: An error if the subscription update fails.
    public func updatePersistentSubscription(stream streamIdentifier: StreamIdentifier, groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Update.Options) -> PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Update.Options = { $0 }) async throws {
        let options = configure(.init())
        try await streams(of: .specified(streamIdentifier))
            .persistentSubscriptions(group: groupName)
            .update(options: options)
    }

    /// Updates an existing persistent subscription for the all-stream.
    ///
    /// - Parameters:
    ///   - groupName: The name of the subscription group.
    ///   - configure: A closure to configure the update options.
    /// - Throws: An error if the subscription update fails.
    public func updatePersistentSubscriptionToAllStream(groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.AllStream>.AllStream.Update.Options) -> PersistentSubscriptions<PersistentSubscription.AllStream>.AllStream.Update.Options = { $0 }) async throws {
        let options = configure(.init())
        try await streams(of: .all)
            .persistentSubscriptions(group: groupName)
            .update(options: options)
    }

    /// Subscribes to a persistent subscription for a specified stream.
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the stream to subscribe to.
    ///   - groupName: The name of the subscription group.
    ///   - configure: A closure to configure the read options.
    /// - Returns: A subscription object for handling events.
    /// - Throws: An error if the subscription fails.
    public func subscribePersistentSubscription(stream streamIdentifier: StreamIdentifier, groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Read.Options) -> PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Read.Options = { $0 }) async throws -> PersistentSubscriptions<PersistentSubscription.Specified>.Subscription {
        let options = configure(.init())
        let stream = streams(of: .specified(streamIdentifier))
        return try await stream.persistentSubscriptions(group: groupName).subscribe(options: options)
    }

    /// Subscribes to a persistent subscription for the all-stream.
    ///
    /// - Parameters:
    ///   - groupName: The name of the subscription group.
    ///   - configure: A closure to configure the read options.
    /// - Returns: A subscription object for handling events.
    /// - Throws: An error if the subscription fails.
    public func subscribePersistentSubscriptionToAllStreams(groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.AllStream>.AllStream.Read.Options) -> PersistentSubscriptions<PersistentSubscription.AllStream>.AllStream.Read.Options = { $0 }) async throws -> PersistentSubscriptions<PersistentSubscription.AllStream>.Subscription {
        let options = configure(.init())
        let stream = streams(of: .all)
        return try await stream.persistentSubscriptions(group: groupName).subscribe(options: options)
    }

    /// Deletes a persistent subscription for a specified stream.
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the stream.
    ///   - groupName: The name of the subscription group.
    /// - Throws: An error if the deletion fails.
    public func deletePersistentSubscription(stream streamIdentifier: StreamIdentifier, groupName: String) async throws {
        try await streams(of: .specified(streamIdentifier))
            .persistentSubscriptions(group: groupName)
            .delete()
    }

    /// Deletes a persistent subscription for the all-stream.
    ///
    /// - Parameters:
    ///   - groupName: The name of the subscription group.
    /// - Throws: An error if the deletion fails.
    public func deletePersistentSubscriptionToAllStream(groupName: String) async throws {
        try await streams(of: .all)
            .persistentSubscriptions(group: groupName)
            .delete()
    }

    /// Lists persistent subscriptions for a specified stream.
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the stream.
    /// - Returns: An array of subscription information.
    /// - Throws: An error if listing fails.
    public func listPersistentSubscriptions(stream streamIdentifier: StreamIdentifier) async throws -> [PersistentSubscription.SubscriptionInfo] {
        try await persistentSubscriptions.list(for: .stream(streamIdentifier))
    }

    /// Lists persistent subscriptions for the all-stream.
    ///
    /// - Returns: An array of subscription information.
    /// - Throws: An error if listing fails.
    public func listPersistentSubscriptionsToAllStream() async throws -> [PersistentSubscription.SubscriptionInfo] {
        try await persistentSubscriptions.list(for: .stream(.all))
    }

    /// Lists all persistent subscriptions.
    ///
    /// - Returns: An array of subscription information.
    /// - Throws: An error if listing fails.
    public func listAllPersistentSubscription() async throws -> [PersistentSubscription.SubscriptionInfo] {
        try await persistentSubscriptions.list(for: .allSubscriptions)
    }

    /// Restarts the persistent subscription subsystem.
    ///
    /// - Throws: An error if restarting fails.
    public func restartPersistentSubscriptionSubsystem() async throws {
        try await persistentSubscriptions.restartSubsystem()
    }

    /// Creates a persistent subscription for a specified stream using a stream name string.
    ///
    /// - Parameters:
    ///   - streamName: The name of the stream to subscribe to.
    ///   - groupName: The name of the subscription group.
    ///   - configure: A closure to configure the creation options.
    /// - Throws: An error if the subscription creation fails.
    public func createPersistentSubscription(stream streamName: String, groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Create.Options) -> PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Create.Options = { $0 }) async throws {
        let options = configure(.init())
        try await streams(of: .specified(streamName))
            .persistentSubscriptions(group: groupName)
            .create(options: options)
    }

    /// Updates an existing persistent subscription for a specified stream using a stream name string.
    ///
    /// - Parameters:
    ///   - streamName: The name of the stream.
    ///   - groupName: The name of the subscription group.
    ///   - configure: A closure to configure the update options.
    /// - Throws: An error if the subscription update fails.
    public func updatePersistentSubscription(stream streamName: String, groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Update.Options) -> PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Update.Options = { $0 }) async throws {
        let options = configure(.init())
        try await streams(of: .specified(streamName))
            .persistentSubscriptions(group: groupName)
            .update(options: options)
    }

    /// Subscribes to a persistent subscription for a specified stream using a stream name string.
    ///
    /// - Parameters:
    ///   - streamName: The name of the stream to subscribe to.
    ///   - groupName: The name of the subscription group.
    ///   - configure: A closure to configure the read options.
    /// - Returns: A subscription object for handling events.
    /// - Throws: An error if the subscription fails.
    public func subscribePersistentSubscription(stream streamName: String, groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Read.Options) -> PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Read.Options = { $0 }) async throws -> PersistentSubscriptions<PersistentSubscription.Specified>.Subscription {
        let options = configure(.init())
        let stream = streams(of: .specified(streamName))
        return try await stream.persistentSubscriptions(group: groupName).subscribe(options: options)
    }

    /// Deletes a persistent subscription for a specified stream using a stream name string.
    ///
    /// - Parameters:
    ///   - streamName: The name of the stream.
    ///   - groupName: The name of the subscription group.
    /// - Throws: An error if the deletion fails.
    public func deletePersistentSubscription(stream streamName: String, groupName: String) async throws {
        try await streams(of: .specified(streamName))
            .persistentSubscriptions(group: groupName)
            .delete()
    }

    /// Lists persistent subscriptions for a specified stream using a stream name string.
    ///
    /// - Parameters:
    ///   - streamName: The name of the stream.
    /// - Returns: An array of subscription information.
    /// - Throws: An error if listing fails.
    public func listPersistentSubscriptions(stream streamName: String) async throws -> [PersistentSubscription.SubscriptionInfo] {
        try await persistentSubscriptions.list(for: .stream(streamName))
    }
}
