//
//  EventRecord.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/2/11.
//
import Foundation
import GRPCEncapsulates

/// Structured event payload prepared for appending to a KurrentDB stream.
public struct EventRecord: Sendable {
    /// Optional unique identifier; when `nil` the server assigns one on write.
    public let id: UUID?

    /// Raw payload bytes whose encoding is described by `schema`.
    public let data: Data

    /// Schema metadata describing how to interpret `data`.
    public let schema: Schema

    /// The properties as they are kept: the members of the custom metadata, and what the
    /// deprecated setters stored without checking it.
    var storedProperties: [String: Codable & Sendable]

    /// The record's metadata as key-value properties; keys prefixed with `$` are system-reserved.
    ///
    /// String, boolean and number members of the custom metadata read back as `String`, `Bool`,
    /// `Int` or `Double`. Set the metadata when the record is created, through `customMetadata:`.
    public var properties: [String: Codable & Sendable] {
        get {
            storedProperties
        }
        @available(*, deprecated, message: "Create the record with `customMetadata: .json(value)`, which checks the value at once. Removed in 4.0.")
        set {
            storedProperties = newValue
        }
    }

    /// Every public initializer ends here.
    init(id: UUID?, data: Data, schema: Schema, storedProperties: [String: Codable & Sendable]) {
        self.id = id
        self.data = data
        self.schema = schema
        self.storedProperties = storedProperties
    }

    /// The members of `metadataObject`, a JSON object, as properties. `nil` and empty data mean
    /// no metadata.
    static func properties(fromJSONObject metadataObject: Data?) throws -> [String: Codable & Sendable] {
        guard let metadataObject, !metadataObject.isEmpty else {
            return [:]
        }
        return try JSONDecoder()
            .decode([String: PropertyValue].self, from: metadataObject)
            .mapValues(\.unwrapped)
    }

    /// The members of `customMetadata` as properties, for the initializers that take a `CustomMetadata`.
    static func properties(from customMetadata: CustomMetadata<some EventRecordMetadataFormat>) throws(KurrentError) -> [String: Codable & Sendable] {
        do {
            return try properties(fromJSONObject: customMetadata.data)
        } catch let error as DecodingError {
            throw .decodingError(cause: error)
        } catch {
            throw .internalParsingError(reason: "The custom metadata is not a JSON object: \(error)")
        }
    }

    /// Creates a record from a payload and the JSON object holding its metadata. The metadata is
    /// read before the payload is encoded, so invalid metadata is the error reported first.
    init(id: UUID?, eventType: String, payload: Payload, metadataObject: Data?) throws {
        let properties = try Self.properties(fromJSONObject: metadataObject)
        try self.init(id: id, data: payload.data, schema: .init(format: payload.format, name: eventType), storedProperties: properties)
    }
}

// MARK: - From bytes and a schema

extension EventRecord {
    /// Creates a record from raw bytes and schema metadata.
    ///
    /// - Parameters:
    ///   - id: Optional unique identifier; defaults to `nil` so the server can assign one.
    ///   - data: Raw payload bytes whose encoding matches `schema.format`.
    ///   - schema: Schema metadata describing the payload's format and name.
    public init(id: UUID? = nil, data: Data, schema: Schema) {
        self.init(id: id, data: data, schema: schema, storedProperties: [:])
    }

    /// Creates a record from raw bytes, schema metadata and custom metadata.
    ///
    /// - Parameters:
    ///   - id: Optional unique identifier; defaults to `nil` so the server can assign one.
    ///   - data: Raw payload bytes whose encoding matches `schema.format`.
    ///   - schema: Schema metadata describing the payload's format and name.
    ///   - customMetadata: A JSON object whose members become `properties`; keys starting with `$`
    ///     are system-reserved.
    /// - Throws: `KurrentError.decodingError` if `customMetadata` is not a JSON object.
    public init(id: UUID? = nil, data: Data, schema: Schema, customMetadata: CustomMetadata<some EventRecordMetadataFormat>) throws(KurrentError) {
        try self.init(id: id, data: data, schema: schema, storedProperties: Self.properties(from: customMetadata))
    }
}

// MARK: - From an event type and a payload

extension EventRecord {
    /// Creates a record from a logical event type and typed payload, inferring the schema format automatically.
    ///
    /// ```swift
    /// let record = try EventRecord(
    ///     eventType: "order-placed",
    ///     payload: .json(OrderPlaced(orderId: "123", total: 42.0))
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - id: Optional unique identifier; defaults to `nil` so the server can assign one.
    ///   - eventType: Logical schema name set as `schema.name` (e.g., `"order-placed"`).
    ///   - payload: Typed payload; its format is inferred and used to populate `schema.format`.
    /// - Throws: `EncodingError` if the payload cannot be JSON-encoded.
    public init(id: UUID? = nil, eventType: String, payload: Payload) throws {
        try self.init(id: id, data: payload.data, schema: .init(format: payload.format, name: eventType), storedProperties: [:])
    }

    /// Creates a record from a logical event type, a typed payload and custom metadata.
    ///
    /// ```swift
    /// struct OrderMetadata: Codable, Sendable {
    ///     var tenant: String
    /// }
    ///
    /// let record = try EventRecord(
    ///     eventType: "order-placed",
    ///     payload: .json(["orderId": "123"]),
    ///     customMetadata: .json(OrderMetadata(tenant: "acme"))
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - id: Optional unique identifier; defaults to `nil` so the server can assign one.
    ///   - eventType: Logical schema name set as `schema.name` (e.g., `"order-placed"`).
    ///   - payload: Typed payload; its format is inferred and used to populate `schema.format`.
    ///   - customMetadata: A JSON object whose members become `properties`; keys starting with `$`
    ///     are system-reserved. An invalid value is refused here, not when the record is appended.
    /// - Throws: `KurrentError.decodingError` if `customMetadata` is not a JSON object, or
    ///   `EncodingError` if the payload cannot be JSON-encoded. The metadata is checked first.
    public init(id: UUID? = nil, eventType: String, payload: Payload, customMetadata: CustomMetadata<some EventRecordMetadataFormat>) throws {
        let properties = try Self.properties(from: customMetadata)
        try self.init(id: id, data: payload.data, schema: .init(format: payload.format, name: eventType), storedProperties: properties)
    }

    /// Creates a record with custom metadata given as the bytes of a JSON object.
    ///
    /// - Throws: `EncodingError` if the payload cannot be JSON-encoded, or `DecodingError` if
    ///   `customMetadata` is not a JSON object or nests arrays and objects more than 64 levels deep.
    @available(*, deprecated, message: "Pass a CustomMetadata: `try .json(value)`, or `try CustomMetadata(data: data, format: .json)` for JSON you already have. Leave the argument out for no metadata. Removed in 4.0.")
    public init(id: UUID? = nil, eventType: String, payload: Payload, customMetadata: Data?) throws {
        try self.init(id: id, eventType: eventType, payload: payload, metadataObject: customMetadata)
    }
}

extension EventRecord: Buildable {
    /// Returns a copy of the record with the OpenTelemetry trace ID set.
    ///
    /// - Parameter value: W3C Trace Context trace ID string.
    public func traceId(_ value: String) -> Self {
        withCopy {
            $0.storedProperties["$trace-id"] = value
        }
    }

    /// Returns a copy of the record with the OpenTelemetry span ID set.
    ///
    /// - Parameter value: W3C Trace Context span ID string.
    public func spanId(_ value: String) -> Self {
        withCopy {
            $0.storedProperties["$span-id"] = value
        }
    }

    /// Returns a copy of the record with the ISO 8601 timestamp set.
    ///
    /// - Parameter value: ISO 8601 timestamp string (e.g., `"2026-02-11T10:00:00Z"`).
    public func timestamp(_ value: String) -> Self {
        withCopy {
            $0.storedProperties["$timestamp"] = value
        }
    }

    /// Returns a copy of the record with an arbitrary property value set.
    ///
    /// The value is not checked here: one that cannot be sent, such as a `Double` that is not
    /// finite, fails when the record is appended.
    ///
    /// - Parameters:
    ///   - value: The property value; must be `Codable` and `Sendable`.
    ///   - key: The property key; must not start with `$` for user-defined properties.
    @available(*, deprecated, message: "Create the record with `customMetadata: .json(value)`, which checks the value at once. Removed in 4.0.")
    public func setValue(_ value: Codable & Sendable, forKey key: String) -> Self {
        withCopy {
            $0.storedProperties[key] = value
        }
    }
}

extension EventRecord {
    /// Typed container for an event record's raw bytes or Codable model payload.
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

        /// Schema format inferred from the payload case.
        public var format: Schema.Format {
            switch self {
            case .data:
                .bytes
            case .json:
                .json
            }
        }
    }
}

extension EventRecord.Schema {
    /// Encoding format of an event record's payload bytes.
    public enum Format: Int, Sendable {
        /// No explicit format declared; avoid in production.
        case unspecified = 0

        /// UTF-8 JSON encoding.
        case json = 1

        /// Protocol Buffers binary encoding.
        case protobuf = 2

        /// Apache Avro encoding.
        case avro = 3

        /// Opaque byte sequence with no declared higher-level format.
        case bytes = 4
    }
}

extension EventRecord {
    /// Schema metadata describing the encoding format and logical name of an event record's payload.
    public struct Schema: Sendable {
        /// Encoding format of the payload bytes.
        public let format: Format

        /// Logical schema name identifying the payload contract (replaces the legacy “event type”).
        public let name: String

        /// Optional schema version or registry identifier; omit when schema validation is not enforced.
        public let id: String?

        /// Creates schema metadata with a format, name, and optional version identifier.
        ///
        /// - Parameters:
        ///   - format: Encoding format of the payload.
        ///   - name: Logical schema name (e.g., `”order-placed”`, `”com.acme.orders.placed”`).
        ///   - id: Optional schema version or registry identifier.
        public init(format: Format, name: String, id: String? = nil) {
            self.format = format
            self.name = name
            self.id = id
        }
    }
}
