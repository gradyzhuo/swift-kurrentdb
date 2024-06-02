//
//  RecordedEvent.swift
//
//
//  Created by 卓俊諺 on 2024/6/2.
//

import Foundation

public struct RecordedEvent: EventStoreEvent, Sendable {
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
