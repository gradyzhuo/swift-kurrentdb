//
//  KurrentDBClient+PersistentSubscriptions.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/5/23.
//

/// Provides convenience methods for persistent subscription operations.
extension KurrentDBClient {
    /// Creates a persistent subscription to a specific stream.
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the target stream.
    ///   - groupName: The name of the subscription group.
    ///   - cursor: The starting revision for the subscription, defaulting to `.end`.
    ///   - configure: A closure to customize the creation options, defaulting to no modifications.
    /// - Throws: An error if the creation fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func createPersistentSubscription(stream streamIdentifier: StreamIdentifier, groupName: String, since cursor: RevisionCursor = .end, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.Specified>.Create.Options) -> PersistentSubscriptions<PersistentSubscription.Specified>.Create.Options = { $0 }) async throws {
        let options = configure(.init())
        try await streams(of: .specified(streamIdentifier))
            .persistentSubscriptions(group: groupName)
            .create(startFrom: cursor, options: options)
    }
    
    /// Creates a persistent subscription to all streams.
    ///
    /// - Parameters:
    ///   - groupName: The name of the subscription group.
    ///   - cursor: The starting position for the subscription, defaulting to `.start`.
    ///   - configure: A closure to customize the creation options, defaulting to no modifications.
    /// - Throws: An error if the creation fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func createPersistentSubscriptionToAllStream(groupName: String, since cursor: PositionCursor = .start, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.AllStream>.Create.Options) -> PersistentSubscriptions<PersistentSubscription.AllStream>.Create.Options = { $0 }) async throws {
        let options = configure(.init())
        try await streams(of: .all)
            .persistentSubscriptions(group: groupName)
            .create(startFrom: cursor, options: options)
    }
    
    /// Updates a persistent subscription for a specific stream.
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the target stream.
    ///   - groupName: The name of the subscription group.
    ///   - cursor: The starting revision for the subscription, defaulting to `.end`.
    ///   - configure: A closure to customize the update options, defaulting to no modifications.
    /// - Throws: An error if the update fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func updatePersistentSubscription(stream streamIdentifier: StreamIdentifier, groupName: String, since cursor: RevisionCursor = .end, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.Specified>.Update.Options) -> PersistentSubscriptions<PersistentSubscription.Specified>.Update.Options = { $0 }) async throws {
        let options = configure(.init())
        try await streams(of: .specified(streamIdentifier))
            .persistentSubscriptions(group: groupName)
            .update(startFrom: cursor, options: options)
    }
    
    /// Updates a persistent subscription for all streams.
    ///
    /// - Parameters:
    ///   - groupName: The name of the subscription group.
    ///   - cursor: The starting position for the subscription, defaulting to `.start`.
    ///   - configure: A closure to customize the update options, defaulting to no modifications.
    /// - Throws: An error if the update fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func updatePersistentSubscriptionToAllStream(groupName: String, since cursor: PositionCursor = .start, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.AllStream>.Update.Options) -> PersistentSubscriptions<PersistentSubscription.AllStream>.Update.Options = { $0 }) async throws {
        let options = configure(.init())
        try await streams(of: .all)
            .persistentSubscriptions(group: groupName)
            .update(startFrom: cursor, options: options)
    }
    
    /// Subscribes to a persistent subscription for a specific stream.
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the target stream.
    ///   - groupName: The name of the subscription group.
    ///   - configure: A closure to customize the read options, defaulting to no modifications.
    /// - Returns: A `Subscription` instance for receiving events.
    /// - Throws: An error if the subscription fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func subscribePersistentSubscription(stream streamIdentifier: StreamIdentifier, groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.Specified>.ReadOptions) -> PersistentSubscriptions<PersistentSubscription.Specified>.ReadOptions = { $0 }) async throws -> PersistentSubscriptions<PersistentSubscription.Specified>.Subscription {
        let options = configure(.init())
        let stream = streams(of: .specified(streamIdentifier))
        return try await stream.persistentSubscriptions(group: groupName).subscribe(options: options)
    }
    
    /// Subscribes to a persistent subscription for all streams.
    ///
    /// - Parameters:
    ///   - groupName: The name of the subscription group.
    ///   - configure: A closure to customize the read options, defaulting to no modifications.
    /// - Returns: A `Subscription` instance for receiving events.
    /// - Throws: An error if the subscription fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func subscribePersistentSubscriptionToAllStreams(groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.AllStream>.ReadOptions) -> PersistentSubscriptions<PersistentSubscription.AllStream>.ReadOptions = { $0 }) async throws -> PersistentSubscriptions<PersistentSubscription.AllStream>.Subscription {
        let options = configure(.init())
        let stream = streams(of: .all)
        return try await stream.persistentSubscriptions(group: groupName).subscribe(options: options)
    }
    
    /// Deletes a persistent subscription for a specific stream.
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the target stream.
    ///   - groupName: The name of the subscription group.
    /// - Throws: An error if the deletion fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func deletePersistentSubscription(stream streamIdentifier: StreamIdentifier, groupName: String) async throws {
        try await streams(of: .specified(streamIdentifier))
            .persistentSubscriptions(group: groupName)
            .delete()
    }
    
    /// Deletes a persistent subscription for all streams.
    ///
    /// - Parameter groupName: The name of the subscription group.
    /// - Throws: An error if the deletion fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func deletePersistentSubscriptionToAllStream(groupName: String) async throws {
        try await streams(of: .all)
            .persistentSubscriptions(group: groupName)
            .delete()
    }
    
    /// Lists persistent subscriptions for a specific stream.
    ///
    /// - Parameter streamIdentifier: The identifier of the target stream.
    /// - Returns: An array of `PersistentSubscription.SubscriptionInfo` objects.
    /// - Throws: An error if the list operation fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func listPersistentSubscriptions(stream streamIdentifier: StreamIdentifier) async throws -> [PersistentSubscription.SubscriptionInfo] {
        return try await persistentSubscriptions.list(for: .stream(streamIdentifier))
    }
    
    /// Lists persistent subscriptions for all streams.
    ///
    /// - Returns: An array of `PersistentSubscription.SubscriptionInfo` objects.
    /// - Throws: An error if the list operation fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func listPersistentSubscriptionsToAllStream() async throws -> [PersistentSubscription.SubscriptionInfo] {
        return try await persistentSubscriptions.list(for: .stream(.all))
    }
    
    /// Lists all persistent subscriptions in the system.
    ///
    /// - Returns: An array of `PersistentSubscription.SubscriptionInfo` objects.
    /// - Throws: An error if the list operation fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func listAllPersistentSubscription() async throws -> [PersistentSubscription.SubscriptionInfo] {
        return try await persistentSubscriptions.list(for: .allSubscriptions)
    }
    
    /// Restarts the persistent subscription subsystem.
    ///
    /// - Throws: An error if the restart operation fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func restartPersistentSubscriptionSubsystem() async throws {
        try await persistentSubscriptions.restartSubsystem()
    }
    
    /// Creates a persistent subscription to a specific stream using its name.
    ///
    /// - Parameters:
    ///   - streamName: The name of the target stream.
    ///   - groupName: The name of the subscription group.
    ///   - cursor: The starting revision for the subscription, defaulting to `.end`.
    ///   - configure: A closure to customize the creation options, defaulting to no modifications.
    /// - Throws: An error if the creation fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func createPersistentSubscription(stream streamName: String, groupName: String, since cursor: RevisionCursor = .end, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.Specified>.Create.Options) -> PersistentSubscriptions<PersistentSubscription.Specified>.Create.Options = { $0 }) async throws {
        let options = configure(.init())
        try await streams(of: .specified(streamName))
            .persistentSubscriptions(group: groupName)
            .create(startFrom: cursor, options: options)
    }
    
    /// Updates a persistent subscription for a specific stream using its name.
    ///
    /// - Parameters:
    ///   - streamName: The name of the target stream.
    ///   - groupName: The name of the subscription group.
    ///   - cursor: The starting revision for the subscription, defaulting to `.end`.
    ///   - configure: A closure to customize the update options, defaulting to no modifications.
    /// - Throws: An error if the update fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func updatePersistentSubscription(stream streamName: String, groupName: String, since cursor: RevisionCursor = .end, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.Specified>.Update.Options) -> PersistentSubscriptions<PersistentSubscription.Specified>.Update.Options = { $0 }) async throws {
        let options = configure(.init())
        try await streams(of: .specified(streamName))
            .persistentSubscriptions(group: groupName)
            .update(startFrom: cursor, options: options)
    }
    
    /// Subscribes to a persistent subscription for a specific stream using its name.
    ///
    /// - Parameters:
    ///   - streamName: The name of the target stream.
    ///   - groupName: The name of the subscription group.
    ///   - configure: A closure to customize the read options, defaulting to no modifications.
    /// - Returns: A `Subscription` instance for receiving events.
    /// - Throws: An error if the subscription fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func subscribePersistentSubscription(stream streamName: String, groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.Specified>.ReadOptions) -> PersistentSubscriptions<PersistentSubscription.Specified>.ReadOptions = { $0 }) async throws -> PersistentSubscriptions<PersistentSubscription.Specified>.Subscription {
        let options = configure(.init())
        let stream = streams(of: .specified(streamName))
        return try await stream.persistentSubscriptions(group: groupName).subscribe(options: options)
    }

    /// Deletes a persistent subscription for a specific stream using its name.
    ///
    /// - Parameters:
    ///   - streamName: The name of the target stream.
    ///   - groupName: The name of the subscription group.
    /// - Throws: An error if the deletion fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func deletePersistentSubscription(stream streamName: String, groupName: String) async throws {
        try await streams(of: .specified(streamName))
            .persistentSubscriptions(group: groupName)
            .delete()
    }
    
    /// Lists persistent subscriptions for a specific stream using its name.
    ///
    /// - Parameter streamName: The name of the target stream.
    /// - Returns: An array of `PersistentSubscription.SubscriptionInfo` objects.
    /// - Throws: An error if the list operation fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func listPersistentSubscriptions(stream streamName: String) async throws -> [PersistentSubscription.SubscriptionInfo] {
        return try await persistentSubscriptions.list(for: .stream(streamName))
    }
}
