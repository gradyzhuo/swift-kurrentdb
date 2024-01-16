//
//  EventData.swift
//
//
//  Created by Grady Zhuo on 2023/10/17.
//

import AnyCodable
import Foundation
import GRPCSupport

public enum ContentType: String, Codable {
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
    }

    public private(set) var id: UUID
    public private(set) var eventType: String
    public private(set) var data: Data
    public private(set) var contentType: ContentType = .json
    public private(set) var customMetadata: [String: Codable]

    public var metaData: [String: String] {
        [
            "content-type": contentType.rawValue,
            "eventType": eventType,
        ]
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let uuidString = try container.decode(String.self, forKey: .id)
        guard let id = UUID(uuidString: uuidString) else {
            throw ClientError.eventDataError(message: "Couldn't parsed id from jsonData.")
        }

        let eventType = try container.decode(String.self, forKey: .eventType)
        let content = try container.decode([String: AnyCodable].self, forKey: .data)

        try self.init(id: id, eventType: eventType, content: content)
    }

    public init(id: UUID, eventType: String, data: Data, contentType: ContentType, customMetadata: [String: Codable] = [:]) {
        self.id = id
        self.eventType = eventType
        self.data = data
        self.contentType = contentType
        self.customMetadata = customMetadata
    }

    public init(id: UUID, eventType: String, content: Codable, customMetadata: [String: Codable] = [:]) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(content)
        self.init(id: id, eventType: eventType, data: data, contentType: .json, customMetadata: customMetadata)
    }

    public init(id: UUID = .init(), eventType: String, jsonData: Data, customMetadata: [String: Codable] = [:]) {
        self.init(id: id, eventType: eventType, data: jsonData, contentType: .json, customMetadata: customMetadata)
    }

    public init(id: UUID = .init(), eventType: String, jsonString: String, customMetadata: [String: Codable] = [:], encoding: String.Encoding = .utf8) throws {
        guard let data = jsonString.data(using: encoding) else {
            throw ClientError.eventDataError(message: "The jsonString can't encode to binary data. \(jsonString)")
        }
        self.init(id: id, eventType: eventType, data: data, contentType: .json, customMetadata: customMetadata)
    }

    public static func events(fromJSONString jsonString: String, encoding: String.Encoding = .utf8, customMetadata _: [String: Codable] = [:]) throws -> [Self] {
        guard let data = jsonString.data(using: encoding) else {
            throw ClientError.eventDataError(message: "The jsonString can't encode to binary data. \(jsonString)")
        }

        return try events(fromJSONData: data)
    }

    public static func event(fromJSONString jsonString: String, encoding: String.Encoding = .utf8, customMetadata _: [String: Codable] = [:]) throws -> Self {
        guard let data = jsonString.data(using: encoding) else {
            throw ClientError.eventDataError(message: "The jsonString can't encode to binary data. \(jsonString)")
        }

        return try event(fromJSONData: data)
    }

    public static func events(fromJSONData jsonData: Data, encoding _: String.Encoding = .utf8, customMetadata: [String: Codable] = [:]) throws -> [Self] {
        let decoder = JSONDecoder()
        return try decoder.decode([Self].self, from: jsonData).map {
            var event = $0
            event.customMetadata = customMetadata
            return event
        }
    }

    public static func event(fromJSONData jsonData: Data, encoding _: String.Encoding = .utf8, customMetadata: [String: Codable] = [:]) throws -> Self {
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
    public private(set) var streamIdentifier: StreamClient.Identifier
    public private(set) var revision: UInt64
    public private(set) var position: StreamClient.Position

    public var metadata: [String: String] {
        [
            "type": eventType,
            "content-type": contentType.rawValue,
        ]
    }

    public private(set) var customMetadata: Data
    public private(set) var data: Data

    public func decodeContent<T: Decodable>(to decodeType: T.Type) throws -> T? {
        switch contentType {
        case .json:
            let decoder = JSONDecoder()
            return try decoder.decode(decodeType, from: data)
        default:
            return nil
        }
    }

    init(id: UUID, eventType: String, contentType: ContentType, streamIdentifier: StreamClient.Identifier, revision: UInt64, position: StreamClient.Position, data: Data, customMetadata: Data) {
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
        let position = StreamClient.Position(commit: message.commitPosition, prepare: message.preparePosition)

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
        let position = StreamClient.Position(commit: message.commitPosition, prepare: message.preparePosition)

        self.init(id: id, eventType: eventType, contentType: contentType, streamIdentifier: streamIdentifier, revision: revision, position: position, data: message.data, customMetadata: message.customMetadata)
    }
}

public struct ReadEvent {
    public private(set) var event: RecordedEvent
    public private(set) var link: RecordedEvent?
    public private(set) var commitPosition: StreamClient.Position?

    public var noPosition: Bool {
        commitPosition == nil
    }

    init(event: RecordedEvent, link: RecordedEvent? = nil, commitPosition: StreamClient.Position? = nil) {
        self.event = event
        self.link = link
        self.commitPosition = commitPosition
    }

    init(message: EventStore_Client_Streams_ReadResp.ReadEvent) throws {
        event = try .init(message: message.event)
        link = try message.hasLink ? .init(message: message.link) : nil

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

    init(message: EventStore_Client_PersistentSubscriptions_ReadResp.ReadEvent) throws {
        event = try .init(message: message.event)
        link = try message.hasLink ? .init(message: message.link) : nil

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
