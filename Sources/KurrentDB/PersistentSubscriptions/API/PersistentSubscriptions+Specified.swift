//
//  PersistentSubscriptions+Specified.swift
//  swift-kurrentdb
//

// MARK: - Specified Stream Operations

extension PersistentSubscriptions where Target == SpecifiedPersistentSubscriptionTarget {
    /// The group name of the persistent subscription.
    public var group: String {
        target.group
    }

    /// Creates a persistent subscription for a specified stream with the given options.
    ///
    /// - Parameter configure: A closure to configure creation options. Defaults to no-op.
    /// - Throws: `KurrentError` if the subscription could not be created.
    public func create(configure: @Sendable (inout SpecifiedStream.Create.Options) -> Void = { _ in }) async throws(KurrentError) {
        var options = SpecifiedStream.Create.Options()
        configure(&options)
        let usecase = SpecifiedStream.Create(streamIdentifier: target.identifier, group: group, options: options)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Updates the persistent subscription for the specified stream with the provided options.
    ///
    /// - Parameter configure: A closure to configure update options. Defaults to no-op.
    /// - Throws: `KurrentError` if the update operation fails.
    public func update(configure: @Sendable (inout SpecifiedStream.Update.Options) -> Void = { _ in }) async throws(KurrentError) {
        var options = SpecifiedStream.Update.Options()
        configure(&options)
        let usecase = SpecifiedStream.Update(streamIdentifier: target.identifier, group: group, options: options)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Deletes the persistent subscription for the specified stream and group.
    ///
    /// - Throws: `KurrentError` if the deletion fails.
    public func delete() async throws(KurrentError) {
        let usecase = SpecifiedStream.Delete(streamIdentifier: target.identifier, group: target.group)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Retrieves information about the persistent subscription for the specified stream and group.
    ///
    /// - Returns: Subscription information for the targeted stream and group.
    /// - Throws: `KurrentError` if the operation fails.
    public func getInfo() async throws(KurrentError) -> PersistentSubscription.SubscriptionInfo {
        let usecase = SpecifiedStream.GetInfo(stream: target.identifier, group: group)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Subscribes to a persistent subscription on a specified stream.
    ///
    /// - Parameter configure: A closure to configure subscription options. Defaults to no-op.
    /// - Returns: A `Subscription` representing the active persistent subscription.
    /// - Throws: `KurrentError` if the subscription could not be established.
    public func subscribe(configure: @Sendable (inout SpecifiedStream.Read.Options) -> Void = { _ in }) async throws(KurrentError) -> Subscription {
        var options = SpecifiedStream.Read.Options()
        configure(&options)
        let usecase = SpecifiedStream.Read(stream: target.identifier, group: group, options: options)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Replays parked messages for the specified persistent subscription stream.
    ///
    /// - Parameter configure: A closure to configure replay options. Defaults to no-op.
    /// - Throws: `KurrentError` if the replay operation fails.
    public func replayParked(configure: @Sendable (inout SpecifiedStream.ReplayParked.Options) -> Void = { _ in }) async throws(KurrentError) {
        var options = SpecifiedStream.ReplayParked.Options()
        configure(&options)
        let usecase = SpecifiedStream.ReplayParked(stream: target.identifier, group: group, options: options)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }
}
