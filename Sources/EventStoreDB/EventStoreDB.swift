// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation

public typealias Client = EventStoreDBClient

public func using(settings: ClientSettings) {
    EventStore.shared.settings = settings
}

