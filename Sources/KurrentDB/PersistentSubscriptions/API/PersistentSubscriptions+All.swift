//
//  PersistentSubscriptions+All.swift
//  swift-kurrentdb
//

// MARK: - All Operations

extension PersistentSubscriptions where Target == AllPersistentSubscriptionTarget {

    /// Lists all persistent subscriptions on the server.
    ///
    /// - Returns: An array of `SubscriptionInfo` describing every persistent subscription.
    /// - Throws: `KurrentError` if the request fails.
    public func list() async throws(KurrentError) -> [PersistentSubscription.SubscriptionInfo] {
        let usecase = ListForAll(filter: .stream(.all))
        return try await usecase.perform(selector: selector, callOptions: callOptions, credentials: overrideCredentials)
    }

    /// Restarts the persistent subscriptions subsystem on the server.
    ///
    /// - Throws: `KurrentError` if the restart request fails.
    @MainActor
    public func restartSubsystem() async throws(KurrentError) {
        let usecase = RestartSubsystem()
        _ = try await usecase.perform(selector: selector, callOptions: callOptions, credentials: overrideCredentials)
    }
}
