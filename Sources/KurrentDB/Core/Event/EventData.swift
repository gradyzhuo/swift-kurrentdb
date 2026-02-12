//
//  EventData.swift
//  KurrentCore
//
//  Created by Grady Zhuo on 2023/10/17.
//

import Foundation
import GRPCEncapsulates

public struct EventData: EventStoreEvent {
    public private(set) var id: UUID
    public private(set) var eventType: String
    public private(set) var payload: Payload
    public private(set) var customMetadata: Data?

    public private(set) var metadata: [String: String]

    public init(id: UUID = .init(), eventType: String, payload: Payload, customMetadata: Data? = nil) {
        self.id = id
        self.eventType = eventType
        self.payload = payload
        self.customMetadata = customMetadata

        metadata = [
            "content-type": payload.contentType.rawValue,
            "type": eventType,
        ]
    }

    @available(*, deprecated)
    public init(id: UUID = .init(), eventType: String, payload: Codable & Sendable, customMetadata: Data? = nil) {
        self.init(id: id, eventType: eventType, payload: .json(payload), customMetadata: customMetadata)
    }

    public init(id: UUID = .init(), eventType: String, model: Codable & Sendable, customMetadata: Data? = nil) {
        self.init(id: id, eventType: eventType, payload: .json(model), customMetadata: customMetadata)
    }

    public init(id: UUID = .init(), eventType: String, data: Data, contentType: ContentType = .json, customMetadata: Data? = nil) {
        self.init(id: id, eventType: eventType, payload: .data(data, contentType), customMetadata: customMetadata)
    }

    public init(id: UUID = .init(), eventType: String, bytes: [UInt8], contentType: ContentType = .json, customMetadata: Data? = nil) {
        self.init(id: id, eventType: eventType, data: .init(bytes), contentType: contentType, customMetadata: customMetadata)
    }
}

extension EventData {
    public enum Payload: Sendable {
        case data(Data, ContentType)
        case json(Codable & Sendable)

        public var contentType: ContentType {
            switch self {
            case let .data(_, contentType):
                contentType
            case .json:
                .json
            }
        }

        public var data: Data {
            get throws {
                switch self {
                case let .data(data, _):
                    data
                case let .json(json):
                    try JSONEncoder().encode(json)
                }
            }
        }
    }
}

extension EventData {
    public init(id: UUID = .init(), like recordedEvent: RecordedEvent) {
        self.init(id: id, eventType: recordedEvent.eventType, data: recordedEvent.data, customMetadata: recordedEvent.customMetadata)
    }
}



extension EventRecord {
    public convenience init(eventData: EventData) throws {
        let payload: Payload = switch eventData.payload {
        case let .data(data, contentType):
            .data(data, contentType)
        case let .json(model):
            .json(model)
        }
        try self.init(id: eventData.id, eventType: eventData.eventType, payload: payload, customMetadata: eventData.customMetadata)
    }
}
