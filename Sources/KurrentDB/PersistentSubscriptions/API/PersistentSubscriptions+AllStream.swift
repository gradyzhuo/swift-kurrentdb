//
//  PersistentSubscriptions+AllStream.swift
//  swift-kurrentdb
//

// MARK: - All Stream Operations

extension PersistentSubscriptions where Target == AllStreamPersistentSubscriptionTarget {
    /// Consumer group name for this `$all`-stream subscription.
    public var group: String {
        target.group
    }

    /// Creates a persistent subscription on the `$all` stream.
    ///
    /// - Parameter configure: Closure that customizes creation options before the request is sent.
    /// - Throws: `KurrentError` if the subscription could not be created.
    public func create(configure: @Sendable (inout AllStream.Create.Options) -> Void = { _ in }) async throws(KurrentError) {
        var options = AllStream.Create.Options()
        configure(&options)
        let usecase = AllStream.Create(group: group, options: options)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Updates the persistent subscription on the `$all` stream.
    ///
    /// - Parameter configure: Closure that customizes update options before the request is sent.
    /// - Throws: `KurrentError` if the update operation fails.
    public func update(configure: @Sendable (inout AllStream.Update.Options) -> Void = { _ in }) async throws(KurrentError) {
        var options = AllStream.Update.Options()
        configure(&options)
        let usecase = AllStream.Update(group: group, options: options)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Deletes the persistent subscription group from the `$all` stream.
    ///
    /// - Throws: `KurrentError` if the deletion fails.
    public func delete() async throws(KurrentError) {
        let usecase = AllStream.Delete(group: group)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Retrieves current statistics and configuration for the `$all`-stream subscription group.
    ///
    /// - Returns: A `SubscriptionInfo` snapshot for this subscription group.
    /// - Throws: `KurrentError` if the request fails.
    public func getInfo() async throws(KurrentError) -> PersistentSubscription.SubscriptionInfo {
        let usecase = AllStream.GetInfo(group: group)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Opens a persistent subscription on the `$all` stream and returns an active handle.
    ///
    /// - Parameter configure: Closure that customizes read options before the connection is opened.
    /// - Returns: A `Subscription` handle for receiving and acknowledging events.
    /// - Throws: `KurrentError` if the subscription could not be established.
    public func subscribe(configure: @Sendable (inout AllStream.Read.Options) -> Void = { _ in }) async throws(KurrentError) -> Subscription<PersistentSubscription.EventResult> {
        var options = AllStream.Read.Options()
        configure(&options)
        let usecase = AllStream.Read(group: group, options: options)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Replays all parked messages for this `$all`-stream subscription group.
    ///
    /// - Parameter configure: Closure that customizes replay options before the request is sent.
    /// - Throws: `KurrentError` if the replay request fails.
    public func replayParked(configure: @Sendable (inout AllStream.ReplayParked.Options) -> Void = { _ in }) async throws(KurrentError) {
        var options = AllStream.ReplayParked.Options()
        configure(&options)
        let usecase = AllStream.ReplayParked(group: group, options: options)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }
}
