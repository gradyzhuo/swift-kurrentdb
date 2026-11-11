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

    /// The bytes of the custom metadata attached to the event, or `nil` when it has none.
    public private(set) var customMetadata: Data?

    /// gRPC metadata headers derived from `payload` and `eventType`.
    public private(set) var metadata: [String: String]

    /// Every public initializer ends here.
    private init(id: UUID, eventType: String, payload: Payload, metadataBytes: Data?) {
        self.id = id
        self.eventType = eventType
        self.payload = payload
        customMetadata = metadataBytes

        metadata = [
            "content-type": payload.contentType.rawValue,
            "type": eventType,
        ]
    }
}

// MARK: - Without custom metadata

extension EventData {
    /// Creates an event with an explicit `Payload` value.
    ///
    /// ```swift
    /// let event = EventData(
    ///     eventType: "order-placed",
    ///     payload: .json(OrderPlaced(orderId: "123"))
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - id: Unique event identifier; defaults to a new random UUID.
    ///   - eventType: Logical schema name for the event.
    ///   - payload: Encoded content and its content type.
    public init(id: UUID = .init(), eventType: String, payload: Payload) {
        self.init(id: id, eventType: eventType, payload: payload, metadataBytes: nil)
    }

    /// Creates an event from a `Codable` model, encoding it as JSON.
    ///
    /// - Parameters:
    ///   - id: Unique event identifier; defaults to a new random UUID.
    ///   - eventType: Logical schema name for the event.
    ///   - model: Codable model to encode as the event payload.
    public init(id: UUID = .init(), eventType: String, model: Codable & Sendable) {
        self.init(id: id, eventType: eventType, payload: .json(model), metadataBytes: nil)
    }

    /// Creates an event from pre-encoded `Data` with an explicit content type.
    ///
    /// - Parameters:
    ///   - id: Unique event identifier; defaults to a new random UUID.
    ///   - eventType: Logical schema name for the event.
    ///   - data: Pre-serialized event payload bytes.
    ///   - contentType: Content type describing the encoding; defaults to `.json`.
    public init(id: UUID = .init(), eventType: String, data: Data, contentType: ContentType = .json) {
        self.init(id: id, eventType: eventType, payload: .data(data, contentType), metadataBytes: nil)
    }

    /// Creates an event from a raw byte array with an explicit content type.
    ///
    /// - Parameters:
    ///   - id: Unique event identifier; defaults to a new random UUID.
    ///   - eventType: Logical schema name for the event.
    ///   - bytes: Raw payload bytes.
    ///   - contentType: Content type describing the encoding; defaults to `.json`.
    public init(id: UUID = .init(), eventType: String, bytes: [UInt8], contentType: ContentType = .json) {
        self.init(id: id, eventType: eventType, payload: .data(.init(bytes), contentType), metadataBytes: nil)
    }
}

// MARK: - With custom metadata

extension EventData {
    /// Creates an event with an explicit `Payload` value and custom metadata.
    ///
    /// ```swift
    /// struct OrderMetadata: Codable, Sendable {
    ///     var tenant: String
    /// }
    ///
    /// let event = EventData(
    ///     eventType: "order-placed",
    ///     payload: .json(["orderId": "123"]),
    ///     customMetadata: try .json(OrderMetadata(tenant: "acme"))
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - id: Unique event identifier; defaults to a new random UUID.
    ///   - eventType: Logical schema name for the event.
    ///   - payload: Encoded content and its content type.
    ///   - customMetadata: Metadata stored next to the event, as JSON or as bytes.
    public init(id: UUID = .init(), eventType: String, payload: Payload, customMetadata: CustomMetadata<some EventDataMetadataFormat>) {
        self.init(id: id, eventType: eventType, payload: payload, metadataBytes: customMetadata.data)
    }

    /// Creates an event from a `Codable` model, encoding it as JSON, with custom metadata.
    ///
    /// - Parameters:
    ///   - id: Unique event identifier; defaults to a new random UUID.
    ///   - eventType: Logical schema name for the event.
    ///   - model: Codable model to encode as the event payload.
    ///   - customMetadata: Metadata stored next to the event, as JSON or as bytes.
    public init(id: UUID = .init(), eventType: String, model: Codable & Sendable, customMetadata: CustomMetadata<some EventDataMetadataFormat>) {
        self.init(id: id, eventType: eventType, payload: .json(model), metadataBytes: customMetadata.data)
    }

    /// Creates an event from pre-encoded `Data` with an explicit content type and custom metadata.
    ///
    /// - Parameters:
    ///   - id: Unique event identifier; defaults to a new random UUID.
    ///   - eventType: Logical schema name for the event.
    ///   - data: Pre-serialized event payload bytes.
    ///   - contentType: Content type describing the encoding; defaults to `.json`.
    ///   - customMetadata: Metadata stored next to the event, as JSON or as bytes.
    public init(id: UUID = .init(), eventType: String, data: Data, contentType: ContentType = .json, customMetadata: CustomMetadata<some EventDataMetadataFormat>) {
        self.init(id: id, eventType: eventType, payload: .data(data, contentType), metadataBytes: customMetadata.data)
    }

    /// Creates an event from a raw byte array with an explicit content type and custom metadata.
    ///
    /// - Parameters:
    ///   - id: Unique event identifier; defaults to a new random UUID.
    ///   - eventType: Logical schema name for the event.
    ///   - bytes: Raw payload bytes.
    ///   - contentType: Content type describing the encoding; defaults to `.json`.
    ///   - customMetadata: Metadata stored next to the event, as JSON or as bytes.
    public init(id: UUID = .init(), eventType: String, bytes: [UInt8], contentType: ContentType = .json, customMetadata: CustomMetadata<some EventDataMetadataFormat>) {
        self.init(id: id, eventType: eventType, payload: .data(.init(bytes), contentType), metadataBytes: customMetadata.data)
    }
}

// MARK: - Deprecated: custom metadata as Data

extension EventData {
    /// Creates an event with custom metadata given as bytes.
    @available(*, deprecated, message: "Pass a CustomMetadata: `try .json(value)`, or `try CustomMetadata(data: data, format: .bytes)` for bytes. Leave the argument out for no metadata. Removed in 4.0.")
    public init(id: UUID = .init(), eventType: String, payload: Payload, customMetadata: Data?) {
        self.init(id: id, eventType: eventType, payload: payload, metadataBytes: customMetadata)
    }

    /// Creates an event from a `Codable` model with custom metadata given as bytes.
    @available(*, deprecated, message: "Pass a CustomMetadata: `try .json(value)`, or `try CustomMetadata(data: data, format: .bytes)` for bytes. Leave the argument out for no metadata. Removed in 4.0.")
    public init(id: UUID = .init(), eventType: String, model: Codable & Sendable, customMetadata: Data?) {
        self.init(id: id, eventType: eventType, payload: .json(model), metadataBytes: customMetadata)
    }

    /// Creates an event from pre-encoded `Data` with custom metadata given as bytes.
    @available(*, deprecated, message: "Pass a CustomMetadata: `try .json(value)`, or `try CustomMetadata(data: data, format: .bytes)` for bytes. Leave the argument out for no metadata. Removed in 4.0.")
    public init(id: UUID = .init(), eventType: String, data: Data, contentType: ContentType = .json, customMetadata: Data?) {
        self.init(id: id, eventType: eventType, payload: .data(data, contentType), metadataBytes: customMetadata)
    }

    /// Creates an event from a raw byte array with custom metadata given as bytes.
    @available(*, deprecated, message: "Pass a CustomMetadata: `try .json(value)`, or `try CustomMetadata(data: data, format: .bytes)` for bytes. Leave the argument out for no metadata. Removed in 4.0.")
    public init(id: UUID = .init(), eventType: String, bytes: [UInt8], contentType: ContentType = .json, customMetadata: Data?) {
        self.init(id: id, eventType: eventType, payload: .data(.init(bytes), contentType), metadataBytes: customMetadata)
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
        self.init(id: id, eventType: recordedEvent.eventType, payload: .data(recordedEvent.data, .json), metadataBytes: recordedEvent.customMetadata)
    }
}

extension EventRecord {
    /// Creates an `EventRecord` from an `EventData` value.
    ///
    /// - Parameter eventData: The source event data to convert.
    /// - Throws: `EncodingError` if the payload cannot be JSON-encoded, or `DecodingError` if the
    ///   event's custom metadata is not a JSON object.
    public init(eventData: EventData) throws {
        let payload: Payload = switch eventData.payload {
        case let .data(data, contentType):
            .data(data, contentType)
        case let .json(model):
            .json(model)
        }
        try self.init(id: eventData.id, data: payload.data, schema: .init(format: payload.format, name: eventData.eventType), metadataObject: eventData.customMetadata)
    }
}
