//
//  EventData.swift
//  KurrentCore
//
//  Created by Grady Zhuo on 2023/10/17.
//

import Foundation
import GRPCEncapsulates

public struct EventData: EventStoreEvent {
    public enum Content: Sendable {
        case binary(Data)
        case json(Codable & Sendable)

        var contentType: String {
            switch self {
            case .binary:
                "application/octet-stream"
            case .json:
                "application/json"
            }
        }

        package var data: Data {
            get throws {
                switch self {
                case let .binary(data):
                    data
                case let .json(json):
                    try JSONEncoder().encode(json)
                }
            }
        }
    }

    public private(set) var id: UUID
    public private(set) var eventType: String
    public private(set) var payload: Content
    public private(set) var customMetadata: Data?

    public private(set) var metadata: [String: String]

    public init(id: UUID = .init(), eventType: String, payload: Content, contentType _: ContentType, customMetadata: Data? = nil) {
        self.id = id
        self.eventType = eventType
        self.payload = payload
        self.customMetadata = customMetadata

        metadata = [
            "content-type": payload.contentType,
            "type": eventType,
        ]
    }

    public init(id: UUID = .init(), eventType: String, payload: Codable & Sendable, customMetadata: Data? = nil) {
        self.init(id: id, eventType: eventType, payload: .json(payload), contentType: .json, customMetadata: customMetadata)
    }
}
