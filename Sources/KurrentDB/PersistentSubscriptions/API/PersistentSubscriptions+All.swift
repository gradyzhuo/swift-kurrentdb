//
//  PersistentSubscriptions+All.swift
//  swift-kurrentdb
//

// MARK: - All Operations

extension PersistentSubscriptions where Target == AllPersistentSubscriptionTarget {

    public func list() async throws(KurrentError) -> [PersistentSubscription.SubscriptionInfo] {
        let usecase = ListForAll(filter: .stream(.all))
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Restarts the subsystem managing persistent subscriptions.
    ///
    /// This operation reinitializes the persistent subscription infrastructure on the server side.
    /// Throws a `KurrentError` if the restart fails.
    @MainActor
    public func restartSubsystem() async throws(KurrentError) {
        let usecase = RestartSubsystem()
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }
}
