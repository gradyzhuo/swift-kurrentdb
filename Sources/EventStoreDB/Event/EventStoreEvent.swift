//
//  EventStoreEvent.swift
//
//
//  Created by 卓俊諺 on 2024/6/2.
//

import Foundation

public protocol EventStoreEvent {
    var id: UUID { get }
    var eventType: String { get }
    var contentType: ContentType { get }
}
