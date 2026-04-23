//
//  PersistentSubscriptions+FilterStream.swift
//  swift-kurrentdb
//

// MARK: - FilterStream Operations

extension PersistentSubscriptions where Target == FilterStreamPersistentSubscriptionTarget {
    /// Lists all persistent subscriptions for the filtered stream.
    ///
    /// - Returns: An array of `SubscriptionInfo` for subscriptions on the target stream.
    /// - Throws: `KurrentError` if the request fails.
    public func list() async throws(KurrentError) -> [PersistentSubscription.SubscriptionInfo] {
        let usecase = ListForAll(filter: .stream(target.stream))
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }
}
