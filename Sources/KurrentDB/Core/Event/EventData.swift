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

    private init(id: UUID = .init(), eventType: String, payload: Payload, contentType _: ContentType, customMetadata: Data? = nil) {
        self.id = id
        self.eventType = eventType
        self.payload = payload
        self.customMetadata = customMetadata

        metadata = [
            "content-type": payload.contentType,
            "type": eventType,
        ]
    }

    @available(*, deprecated)
    public init(id: UUID = .init(), eventType: String, payload: Codable & Sendable, customMetadata: Data? = nil) {
        self.init(id: id, eventType: eventType, payload: .json(payload), contentType: .json, customMetadata: customMetadata)
    }

    public init(id: UUID = .init(), eventType: String, model: Codable & Sendable, customMetadata: Data? = nil) {
        self.init(id: id, eventType: eventType, payload: .json(model), contentType: .json, customMetadata: customMetadata)
    }

    public init(id: UUID = .init(), eventType: String, data: Data, contentType: ContentType = .json, customMetadata: Data? = nil) {
        self.init(id: id, eventType: eventType, payload: .data(data), contentType: contentType, customMetadata: customMetadata)
    }

    public init(id: UUID = .init(), eventType: String, bytes: [UInt8], customMetadata: Data? = nil) {
        self.init(id: id, eventType: eventType, payload: .data(.init(bytes)), contentType: .binary, customMetadata: customMetadata)
    }
}

extension EventData {
    public enum Payload: Sendable {
        case data(Data)
        case json(Codable & Sendable)

        var contentType: String {
            switch self {
            case .data:
                "application/octet-stream"
            case .json:
                "application/json"
            }
        }

        package var data: Data {
            get throws {
                switch self {
                case let .data(data):
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
