//
//  EventStoreEvent.swift
//
//
//  Created by Grady Zhuo on 2024/6/2.
//

import Foundation

public protocol EventStoreEvent {
    var id: UUID { get }
    var eventType: String { get }
    var contentType: ContentType { get }
}
