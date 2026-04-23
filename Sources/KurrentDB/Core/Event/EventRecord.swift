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

    /// Arbitrary key-value metadata; keys prefixed with `$` are system-reserved.
    public var properties: [String: Codable & Sendable]

    /// Creates a record from raw bytes, schema metadata, and optional properties.
    ///
    /// - Parameters:
    ///   - id: Optional unique identifier; defaults to `nil` so the server can assign one.
    ///   - data: Raw payload bytes whose encoding matches `schema.format`.
    ///   - schema: Schema metadata describing the payload's format and name.
    ///   - properties: Additional key-value metadata; keys starting with `$` are system-reserved.
    public init(id: UUID? = nil, data: Data, schema: Schema, properties: [String: Codable & Sendable] = [:]) {
        self.id = id
        self.data = data
        self.schema = schema
        self.properties = properties
    }
}

extension EventRecord {
    /// Creates a record from a logical event type and typed payload, inferring the schema format automatically.
    ///
    /// ```swift
    /// let record = try EventRecord(
    ///     eventType: "order-placed",
    ///     payload: .json(OrderPlaced(id: "123", total: 42.0))
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - id: Optional unique identifier; defaults to `nil` so the server can assign one.
    ///   - eventType: Logical schema name set as `schema.name` (e.g., `"order-placed"`).
    ///   - payload: Typed payload; its format is inferred and used to populate `schema.format`.
    ///   - customMetadata: Optional JSON bytes parsed into `properties`; keys starting with `$` are system-reserved.
    /// - Throws: `KurrentError` if JSON encoding or metadata parsing fails.
    public init(id: UUID? = nil, eventType: String, payload: Payload, customMetadata: Data? = nil) throws {
        let schema = Schema(format: payload.format, name: eventType)
        let properties = try customMetadata.flatMap {
            try JSONSerialization.jsonObject(with: $0) as? [String: Codable & Sendable]
        } ?? [:]
        try self.init(id: id, data: payload.data, schema: schema, properties: properties)
    }
}

extension EventRecord: Buildable {
    /// Returns a copy of the record with the OpenTelemetry trace ID set.
    ///
    /// - Parameter value: W3C Trace Context trace ID string.
    public func traceId(_ value: String) -> Self {
        withCopy {
            $0.properties["$trace-id"] = value
        }
    }

    /// Returns a copy of the record with the OpenTelemetry span ID set.
    ///
    /// - Parameter value: W3C Trace Context span ID string.
    public func spanId(_ value: String) -> Self {
        withCopy {
            $0.properties["$span-id"] = value
        }
    }

    /// Returns a copy of the record with the ISO 8601 timestamp set.
    ///
    /// - Parameter value: ISO 8601 timestamp string (e.g., `"2026-02-11T10:00:00Z"`).
    public func timestamp(_ value: String) -> Self {
        withCopy {
            $0.properties["$timestamp"] = value
        }
    }

    /// Returns a copy of the record with an arbitrary property value set.
    ///
    /// - Parameters:
    ///   - value: The property value; must be `Codable` and `Sendable`.
    ///   - key: The property key; must not start with `$` for user-defined properties.
    public func setValue(_ value: Codable & Sendable, forKey key: String) -> Self {
        withCopy {
            $0.properties[key] = value
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
