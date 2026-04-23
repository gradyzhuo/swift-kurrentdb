//
//  PersistentSubscriptions+Specified.swift
//  swift-kurrentdb
//

// MARK: - Specified Stream Operations

extension PersistentSubscriptions where Target == SpecifiedPersistentSubscriptionTarget {
    /// Consumer group name for this named-stream subscription.
    public var group: String {
        target.group
    }

    /// Creates a persistent subscription on the target stream.
    ///
    /// - Parameter configure: Closure that customizes creation options before the request is sent.
    /// - Throws: `KurrentError` if the subscription could not be created.
    public func create(configure: @Sendable (inout SpecifiedStream.Create.Options) -> Void = { _ in }) async throws(KurrentError) {
        var options = SpecifiedStream.Create.Options()
        configure(&options)
        let usecase = SpecifiedStream.Create(streamIdentifier: target.identifier, group: group, options: options)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Updates the persistent subscription on the target stream.
    ///
    /// - Parameter configure: Closure that customizes update options before the request is sent.
    /// - Throws: `KurrentError` if the update operation fails.
    public func update(configure: @Sendable (inout SpecifiedStream.Update.Options) -> Void = { _ in }) async throws(KurrentError) {
        var options = SpecifiedStream.Update.Options()
        let originInfo = try await getInfo()
        options.settings.update(from: originInfo)
        configure(&options)
        let usecase = SpecifiedStream.Update(streamIdentifier: target.identifier, group: group, options: options)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Deletes the persistent subscription from the target stream.
    ///
    /// - Throws: `KurrentError` if the deletion fails.
    public func delete() async throws(KurrentError) {
        let usecase = SpecifiedStream.Delete(streamIdentifier: target.identifier, group: target.group)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Retrieves current statistics and configuration for the named-stream subscription group.
    ///
    /// - Returns: A `SubscriptionInfo` snapshot for this subscription group.
    /// - Throws: `KurrentError` if the request fails.
    public func getInfo() async throws(KurrentError) -> PersistentSubscription.SubscriptionInfo {
        let usecase = SpecifiedStream.GetInfo(stream: target.identifier, group: group)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Opens a persistent subscription on the target stream and returns an active handle.
    ///
    /// ```swift
    /// let sub = client.persistentSubscriptions(stream: "orders", group: "processors")
    /// try await sub.create()
    /// let subscription = try await sub.subscribe()
    /// for try await result in subscription.events {
    ///     print(result.event.record.eventType)
    ///     try await subscription.ack(readEvents: result.event)
    /// }
    /// ```
    ///
    /// - Parameter configure: Closure that customizes read options before the connection is opened.
    /// - Returns: A `Subscription` handle for receiving and acknowledging events.
    /// - Throws: `KurrentError` if the subscription could not be established.
    public func subscribe(configure: @Sendable (inout SpecifiedStream.Read.Options) -> Void = { _ in }) async throws(KurrentError) -> Subscription<PersistentSubscription.EventResult> {
        var options = SpecifiedStream.Read.Options()
        configure(&options)
        let usecase = SpecifiedStream.Read(stream: target.identifier, group: group, options: options)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Replays all parked messages for this named-stream subscription group.
    ///
    /// - Parameter configure: Closure that customizes replay options before the request is sent.
    /// - Throws: `KurrentError` if the replay request fails.
    public func replayParked(configure: @Sendable (inout SpecifiedStream.ReplayParked.Options) -> Void = { _ in }) async throws(KurrentError) {
        var options = SpecifiedStream.ReplayParked.Options()
        configure(&options)
        let usecase = SpecifiedStream.ReplayParked(stream: target.identifier, group: group, options: options)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }
}
