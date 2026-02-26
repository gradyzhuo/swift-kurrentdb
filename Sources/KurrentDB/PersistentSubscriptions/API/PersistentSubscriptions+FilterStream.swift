//
//  PersistentSubscriptions+FilterStream.swift
//  swift-kurrentdb
//

// MARK: - FilterStream Operations

extension PersistentSubscriptions where Target == FilterStreamPersistentSubscriptionTarget {
    public func list() async throws(KurrentError) -> [PersistentSubscription.SubscriptionInfo] {
        let usecase = ListForAll(filter: .stream(target.stream))
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }
}
