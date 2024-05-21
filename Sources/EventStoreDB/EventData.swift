//
//  EventData.swift
//
//
//  Created by Grady Zhuo on 2023/10/17.
//

import Foundation
import GRPCEncapsulates

public enum ContentType: String, Codable, Sendable {
    case unknown
    case json = "application/json"
    case binary = "application/octet-stream"
}

public protocol EventStoreEvent {
    var id: UUID { get }
    var eventType: String { get }
    var contentType: ContentType { get }
}

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

    public init(eventType: String, payload: Codable, customMetadata: Data? = nil) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(payload)
        self.init(id: .init(), eventType: eventType, data: data, contentType: .json, customMetadata: customMetadata)
    }

    public init(eventType: String, payloadData: Data, customMetadata: Data? = nil) throws {
        self.init(id: .init(), eventType: eventType, data: payloadData, contentType: .binary, customMetadata: customMetadata)
    }

    public static func events(fromJSONString jsonString: String, encoding: String.Encoding = .utf8, customMetadata _: Data? = nil) throws -> [Self] {
        guard let data = jsonString.data(using: encoding) else {
            throw ClientError.eventDataError(message: "The jsonString can't be encoded into binary data. \(jsonString)")
        }

        return try events(fromJSONData: data)
    }

    public static func event(fromJSONString jsonString: String, encoding: String.Encoding = .utf8, customMetadata _: [String: Codable] = [:]) throws -> Self {
        guard let data = jsonString.data(using: encoding) else {
            throw ClientError.eventDataError(message: "The jsonString can't be encoded into binary data. \(jsonString)")
        }

        return try event(fromJSONData: data)
    }

    public static func events(fromJSONData jsonData: Data, encoding _: String.Encoding = .utf8, customMetadata: Data? = nil) throws -> [Self] {
        let decoder = JSONDecoder()
        return try decoder.decode([Self].self, from: jsonData).map {
            var event = $0
            event.customMetadata = customMetadata
            return event
        }
    }

    public static func event(fromJSONData jsonData: Data, encoding _: String.Encoding = .utf8, customMetadata: Data? = nil) throws -> Self {
        let decoder = JSONDecoder()
        var event = try decoder.decode(Self.self, from: jsonData)
        event.customMetadata = customMetadata
        return event
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
            && lhs.contentType == rhs.contentType
            && lhs.eventType == rhs.eventType
    }
}

public struct RecordedEvent: EventStoreEvent {
    public private(set) var id: UUID
    public private(set) var eventType: String
    public private(set) var contentType: ContentType
    public private(set) var streamIdentifier: Stream.Identifier
    public private(set) var revision: UInt64
    public private(set) var position: Stream.Position

    public var metadata: [String: String] {
        [
            "type": eventType,
            "content-type": contentType.rawValue,
        ]
    }

    public private(set) var customMetadata: Data
    public private(set) var data: Data

    public func decode<T: Decodable>(to decodeType: T.Type) throws -> T? {
        switch contentType {
        case .json:
            let decoder = JSONDecoder()
            return try decoder.decode(decodeType, from: data)
        default:
            return nil
        }
    }

    init(id: UUID, eventType: String, contentType: ContentType, streamIdentifier: Stream.Identifier, revision: UInt64, position: Stream.Position, data: Data, customMetadata: Data) {
        self.id = id
        self.eventType = eventType
        self.contentType = contentType
        self.streamIdentifier = streamIdentifier
        self.revision = revision
        self.position = position
        self.customMetadata = customMetadata
        self.data = data
    }

    init(message: EventStore_Client_Streams_ReadResp.ReadEvent.RecordedEvent) throws {
        guard let id = message.id.toUUID() else {
            throw ReadEventError.GRPCDecodeException(message: "RecordedEvent can't convert an UUID from message.id: \(message.id)")
        }

        guard let eventType = message.metadata["type"] else {
            throw ReadEventError.GRPCDecodeException(message: "RecordedEvent can't get an event type from message.metadata: \(message.metadata)")
        }

        let contentType = ContentType(rawValue: message.metadata["content-type"] ?? ContentType.binary.rawValue) ?? .unknown
        let streamIdentifier = message.streamIdentifier.toIdentifier()
        let revision = message.streamRevision
        let position = Stream.Position(commit: message.commitPosition, prepare: message.preparePosition)

        self.init(id: id, eventType: eventType, contentType: contentType, streamIdentifier: streamIdentifier, revision: revision, position: position, data: message.data, customMetadata: message.customMetadata)
    }

    init(message: EventStore_Client_PersistentSubscriptions_ReadResp.ReadEvent.RecordedEvent) throws {
        guard let id = message.id.toUUID() else {
            throw ReadEventError.GRPCDecodeException(message: "RecordedEvent can't convert an UUID from message.id: \(message.id)")
        }

        guard let eventType = message.metadata["type"] else {
            throw ReadEventError.GRPCDecodeException(message: "RecordedEvent can't get an event type from message.metadata: \(message.metadata)")
        }

        let contentType = ContentType(rawValue: message.metadata["content-type"] ?? ContentType.binary.rawValue) ?? .unknown
        let streamIdentifier = message.streamIdentifier.toIdentifier()
        let revision = message.streamRevision
        let position = Stream.Position(commit: message.commitPosition, prepare: message.preparePosition)

        self.init(id: id, eventType: eventType, contentType: contentType, streamIdentifier: streamIdentifier, revision: revision, position: position, data: message.data, customMetadata: message.customMetadata)
    }
}

public struct ReadEvent {
    public internal(set) var recordedEvent: RecordedEvent
    public internal(set) var linkedRecordedEvent: RecordedEvent?
    public internal(set) var commitPosition: Stream.Position?

    public var noPosition: Bool {
        commitPosition == nil
    }

    init(event: RecordedEvent, link: RecordedEvent? = nil, commitPosition: Stream.Position? = nil) {
        recordedEvent = event
        linkedRecordedEvent = link
        self.commitPosition = commitPosition
    }

    init(message: EventStore_Client_Streams_ReadResp.ReadEvent) throws {
        recordedEvent = try .init(message: message.event)
        linkedRecordedEvent = try message.hasLink ? .init(message: message.link) : nil

        if let position = message.position {
            switch position {
            case .noPosition:
                commitPosition = nil
            case let .commitPosition(commitPosition):
                self.commitPosition = .init(commit: commitPosition)
            }
        } else {
            commitPosition = nil
        }
    }
}
