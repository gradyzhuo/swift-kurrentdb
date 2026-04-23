//
//  EventData.swift
//  KurrentCore
//
//  Created by Grady Zhuo on 2023/10/17.
//

import Foundation
import GRPCEncapsulates

/// Event payload prepared for appending to a KurrentDB stream.
public struct EventData: EventStoreEvent {
    /// Unique identifier for this event.
    public private(set) var id: UUID

    /// Logical type name describing the event's schema.
    public private(set) var eventType: String

    /// Encoded payload and its content type.
    public private(set) var payload: Payload

    /// Optional opaque metadata bytes attached to the event.
    public private(set) var customMetadata: Data?

    /// gRPC metadata headers derived from `payload` and `eventType`.
    public private(set) var metadata: [String: String]

    /// Creates an event with an explicit `Payload` value.
    ///
    /// ```swift
    /// let event = EventData(
    ///     eventType: "order-placed",
    ///     payload: .json(OrderPlaced(id: "123"))
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - id: Unique event identifier; defaults to a new random UUID.
    ///   - eventType: Logical schema name for the event.
    ///   - payload: Encoded content and its content type.
    ///   - customMetadata: Optional raw metadata bytes appended alongside the event.
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

    /// Creates an event from a `Codable` model, encoding it as JSON.
    ///
    /// - Parameters:
    ///   - id: Unique event identifier; defaults to a new random UUID.
    ///   - eventType: Logical schema name for the event.
    ///   - model: Codable model to encode as the event payload.
    ///   - customMetadata: Optional raw metadata bytes appended alongside the event.
    public init(id: UUID = .init(), eventType: String, model: Codable & Sendable, customMetadata: Data? = nil) {
        self.init(id: id, eventType: eventType, payload: .json(model), customMetadata: customMetadata)
    }

    /// Creates an event from pre-encoded `Data` with an explicit content type.
    ///
    /// - Parameters:
    ///   - id: Unique event identifier; defaults to a new random UUID.
    ///   - eventType: Logical schema name for the event.
    ///   - data: Pre-serialized event payload bytes.
    ///   - contentType: Content type describing the encoding; defaults to `.json`.
    ///   - customMetadata: Optional raw metadata bytes appended alongside the event.
    public init(id: UUID = .init(), eventType: String, data: Data, contentType: ContentType = .json, customMetadata: Data? = nil) {
        self.init(id: id, eventType: eventType, payload: .data(data, contentType), customMetadata: customMetadata)
    }

    /// Creates an event from a raw byte array with an explicit content type.
    ///
    /// - Parameters:
    ///   - id: Unique event identifier; defaults to a new random UUID.
    ///   - eventType: Logical schema name for the event.
    ///   - bytes: Raw payload bytes.
    ///   - contentType: Content type describing the encoding; defaults to `.json`.
    ///   - customMetadata: Optional raw metadata bytes appended alongside the event.
    public init(id: UUID = .init(), eventType: String, bytes: [UInt8], contentType: ContentType = .json, customMetadata: Data? = nil) {
        self.init(id: id, eventType: eventType, data: .init(bytes), contentType: contentType, customMetadata: customMetadata)
    }
}

extension EventData {
    /// Typed container for an event's raw bytes or Codable model payload.
    public enum Payload: Sendable {
        /// Pre-encoded bytes with an explicit content type.
        case data(Data, ContentType)

        /// A Codable model that will be JSON-encoded on demand.
        case json(Codable & Sendable)

        /// Content type of the payload.
        public var contentType: ContentType {
            switch self {
            case let .data(_, contentType):
                contentType
            case .json:
                .json
            }
        }

        /// Serialized bytes of the payload; throws if JSON encoding fails.
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
    /// Creates a new `EventData` by copying the type, payload, and metadata from a `RecordedEvent`.
    ///
    /// - Parameters:
    ///   - id: Unique event identifier for the new event; defaults to a new random UUID.
    ///   - recordedEvent: The recorded event whose payload and metadata are copied.
    public init(id: UUID = .init(), like recordedEvent: RecordedEvent) {
        self.init(id: id, eventType: recordedEvent.eventType, data: recordedEvent.data, customMetadata: recordedEvent.customMetadata)
    }
}

extension EventRecord {
    /// Creates an `EventRecord` from an `EventData` value, bridging the legacy API to the newer record type.
    ///
    /// - Parameter eventData: The source event data to convert.
    /// - Throws: `EncodingError` if the payload cannot be JSON-encoded.
    public init(eventData: EventData) throws {
        let payload: Payload = switch eventData.payload {
        case let .data(data, contentType):
            .data(data, contentType)
        case let .json(model):
            .json(model)
        }
        try self.init(id: eventData.id, eventType: eventData.eventType, payload: payload, customMetadata: eventData.customMetadata)
    }
}
