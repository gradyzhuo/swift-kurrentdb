//
//  KurrentDBClient+PersistentSubscriptions.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/5/23.
//

extension KurrentDBClient {
    public func createPersistentSubscription(stream streamIdentifier: StreamIdentifier, groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Create.Options) -> PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Create.Options = { $0 }) async throws {
        let options = configure(.init())
        try await streams(of: .specified(streamIdentifier))
            .persistentSubscriptions(group: groupName)
            .create(options: options)
    }

    public func createPersistentSubscriptionToAllStream(groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.AllStream>.AllStream.Create.Options) -> PersistentSubscriptions<PersistentSubscription.AllStream>.AllStream.Create.Options = { $0 }) async throws {
        let options = configure(.init())
        try await streams(of: .all)
            .persistentSubscriptions(group: groupName)
            .create(options: options)
    }

    public func updatePersistentSubscription(stream streamIdentifier: StreamIdentifier, groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Update.Options) -> PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Update.Options = { $0 }) async throws {
        let options = configure(.init())
        try await streams(of: .specified(streamIdentifier))
            .persistentSubscriptions(group: groupName)
            .update(options: options)
    }

    public func updatePersistentSubscriptionToAllStream(groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.AllStream>.AllStream.Update.Options) -> PersistentSubscriptions<PersistentSubscription.AllStream>.AllStream.Update.Options = { $0 }) async throws {
        let options = configure(.init())
        try await streams(of: .all)
            .persistentSubscriptions(group: groupName)
            .update(options: options)
    }

    public func subscribePersistentSubscription(stream streamIdentifier: StreamIdentifier, groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Read.Options) -> PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Read.Options = { $0 }) async throws -> PersistentSubscriptions<PersistentSubscription.Specified>.Subscription {
        let options = configure(.init())
        let stream = streams(of: .specified(streamIdentifier))
        return try await stream.persistentSubscriptions(group: groupName).subscribe(options: options)
    }

    public func subscribePersistentSubscriptionToAllStreams(groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.AllStream>.AllStream.Read.Options) -> PersistentSubscriptions<PersistentSubscription.AllStream>.AllStream.Read.Options = { $0 }) async throws -> PersistentSubscriptions<PersistentSubscription.AllStream>.Subscription {
        let options = configure(.init())
        let stream = streams(of: .all)
        return try await stream.persistentSubscriptions(group: groupName).subscribe(options: options)
    }

    public func deletePersistentSubscription(stream streamIdentifier: StreamIdentifier, groupName: String) async throws {
        try await streams(of: .specified(streamIdentifier))
            .persistentSubscriptions(group: groupName)
            .delete()
    }

    public func deletePersistentSubscriptionToAllStream(groupName: String) async throws {
        try await streams(of: .all)
            .persistentSubscriptions(group: groupName)
            .delete()
    }

    public func listPersistentSubscriptions(stream streamIdentifier: StreamIdentifier) async throws -> [PersistentSubscription.SubscriptionInfo] {
        try await persistentSubscriptions.list(for: .stream(streamIdentifier))
    }

    public func listPersistentSubscriptionsToAllStream() async throws -> [PersistentSubscription.SubscriptionInfo] {
        try await persistentSubscriptions.list(for: .stream(.all))
    }

    public func listAllPersistentSubscription() async throws -> [PersistentSubscription.SubscriptionInfo] {
        try await persistentSubscriptions.list(for: .allSubscriptions)
    }

    public func restartPersistentSubscriptionSubsystem() async throws {
        try await persistentSubscriptions.restartSubsystem()
    }

    public func createPersistentSubscription(stream streamName: String, groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Create.Options) -> PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Create.Options = { $0 }) async throws {
        let options = configure(.init())
        try await streams(of: .specified(streamName))
            .persistentSubscriptions(group: groupName)
            .create(options: options)
    }

    public func updatePersistentSubscription(stream streamName: String, groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Update.Options) -> PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Update.Options = { $0 }) async throws {
        let options = configure(.init())
        try await streams(of: .specified(streamName))
            .persistentSubscriptions(group: groupName)
            .update(options: options)
    }

    public func subscribePersistentSubscription(stream streamName: String, groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Read.Options) -> PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Read.Options = { $0 }) async throws -> PersistentSubscriptions<PersistentSubscription.Specified>.Subscription {
        let options = configure(.init())
        let stream = streams(of: .specified(streamName))
        return try await stream.persistentSubscriptions(group: groupName).subscribe(options: options)
    }

    public func deletePersistentSubscription(stream streamName: String, groupName: String) async throws {
        try await streams(of: .specified(streamName))
            .persistentSubscriptions(group: groupName)
            .delete()
    }

    public func listPersistentSubscriptions(stream streamName: String) async throws -> [PersistentSubscription.SubscriptionInfo] {
        try await persistentSubscriptions.list(for: .stream(streamName))
    }
}
