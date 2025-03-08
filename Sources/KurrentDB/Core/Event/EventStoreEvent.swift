//
//  EventStoreEvent.swift
//  KurrentCore
//
//  Created by Grady Zhuo on 2024/6/2.
//

import Foundation

internal protocol EventStoreEvent: Sendable {
    var id: UUID { get }
    var eventType: String { get }
}
