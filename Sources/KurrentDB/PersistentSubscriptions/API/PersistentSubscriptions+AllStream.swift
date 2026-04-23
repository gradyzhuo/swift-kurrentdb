//
//  PersistentSubscriptions+AllStream.swift
//  swift-kurrentdb
//

// MARK: - All Stream Operations

extension PersistentSubscriptions where Target == AllStreamPersistentSubscriptionTarget {
    /// The group name of the persistent subscription.
    public var group: String {
        target.group
    }

    /// Creates a persistent subscription for all streams with the specified options.
    ///
    /// - Parameter options: Configuration options for creating the persistent subscription. Defaults to the standard options.
    ///
    /// - Throws: `KurrentError` if the subscription could not be created.
    public func create(configure: @Sendable (inout AllStream.Create.Options) -> Void = { _ in }) async throws(KurrentError) {
        var options = AllStream.Create.Options()
        configure(&options)
        let usecase = AllStream.Create(group: group, options: options)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Updates the persistent subscription for all streams with the specified options.
    ///
    /// - Parameter configure: A closure to configure update options. Defaults to no-op.
    /// - Throws: `KurrentError` if the update operation fails.
    public func update(configure: @Sendable (inout AllStream.Update.Options) -> Void = { _ in }) async throws(KurrentError) {
        var options = AllStream.Update.Options()
        configure(&options)
        let usecase = AllStream.Update(group: group, options: options)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Deletes the persistent subscription group for all streams.
    ///
    /// - Throws: `KurrentError` if the deletion fails.
    public func delete() async throws(KurrentError) {
        let usecase = AllStream.Delete(group: group)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Retrieves information about the persistent subscription group for all streams.
    ///
    /// - Returns: Details of the persistent subscription group.
    /// - Throws: `KurrentError` if the operation fails.
    public func getInfo() async throws(KurrentError) -> PersistentSubscription.SubscriptionInfo {
        let usecase = AllStream.GetInfo(group: group)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Subscribes to a persistent subscription for all streams using the specified options.
    ///
    /// - Parameter configure: Configuration options for the subscription. Defaults to no-op.
    /// - Returns: A `Subscription` instance representing the active persistent subscription.
    /// - Throws: `KurrentError` if the subscription could not be established.
    public func subscribe(configure: @Sendable (inout AllStream.Read.Options) -> Void = { _ in }) async throws(KurrentError) -> Subscription<PersistentSubscription.EventResult> {
        var options = AllStream.Read.Options()
        configure(&options)
        let usecase = AllStream.Read(group: group, options: options)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Replays parked messages for the persistent subscription group across all streams.
    ///
    /// - Parameter configure: A closure to configure replay options. Defaults to no-op.
    /// - Throws: `KurrentError` if the operation fails.
    public func replayParked(configure: @Sendable (inout AllStream.ReplayParked.Options) -> Void = { _ in }) async throws(KurrentError) {
        var options = AllStream.ReplayParked.Options()
        configure(&options)
        let usecase = AllStream.ReplayParked(group: group, options: options)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }
}
