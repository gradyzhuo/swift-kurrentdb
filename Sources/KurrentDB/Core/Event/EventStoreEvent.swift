//
//  EventStoreEvent.swift
//  KurrentCore
//
//  Created by Grady Zhuo on 2024/6/2.
//

import Foundation

/// Base protocol for all event types stored in KurrentDB.
protocol EventStoreEvent: Sendable {
    /// Unique identifier for this event.
    var id: UUID { get }

    /// Logical type name describing the event's schema.
    var eventType: String { get }
}
