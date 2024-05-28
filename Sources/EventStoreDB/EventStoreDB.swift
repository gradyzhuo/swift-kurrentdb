// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import Logging

/// Using a client setting to `EventStoreDBClient` by default.
/// - Parameter settings: <#settings description#>
@MainActor
public func using(settings: ClientSettings) {
    EventStore.shared.settings = settings
}

let logger = Logger(label: "ClientSettings")
