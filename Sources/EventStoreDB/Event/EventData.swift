//
//  EventData.swift
//
//
//  Created by Grady Zhuo on 2023/10/17.
//

import Foundation
import GRPCEncapsulates

public struct EventData: EventStoreEvent, Codable, Equatable {
    enum CodingKeys: String, CodingKey {
        case id = "eventId"
        case eventType
        case data
        case contentType
        case customMetadata
    }

    public private(set) var id: UUID
    public private(set) var eventType: String
    public private(set) var data: Data
    public private(set) var contentType: ContentType
    public private(set) var customMetadata: Data?

    public var metadata: [String: String] = [:]

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let uuidString = try container.decode(String.self, forKey: .id)

        guard let id = UUID(uuidString: uuidString) else {
            throw ClientError.eventDataError(message: "Couldn't parsed id from jsonData.")
        }

        let eventType = try container.decode(String.self, forKey: .eventType)
        let data = try container.decode(Data.self, forKey: .data)
        let customMetadata = try container.decodeIfPresent(Data.self, forKey: .customMetadata)

        self.init(id: id, eventType: eventType, data: data, contentType: .json, customMetadata: customMetadata)
    }

    init(id: UUID, eventType: String, data: Data, contentType: ContentType, customMetadata: Data?) {
        self.id = id
        self.eventType = eventType
        self.data = data
        self.contentType = contentType
        metadata = [
            "content-type": ContentType.json.rawValue,
            "type": eventType,
        ]
        self.customMetadata = customMetadata
    }

    public init(id: UUID = .init() ,eventType: String, payload: Codable, customMetadata: Data? = nil) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(payload)
        self.init(id: id, eventType: eventType, data: data, contentType: .json, customMetadata: customMetadata)
    }

    public init(id: UUID = .init(), eventType: String, data: Data, customMetadata: Data? = nil) throws {
        self.init(id: id, eventType: eventType, data: data, contentType: .binary, customMetadata: customMetadata)
    }
}

// MARK: - construction methods

extension EventData {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.contentType == rhs.contentType
            && lhs.eventType == rhs.eventType
            && lhs.data == rhs.data
    }
}
