//
//  EventRecord.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2026/2/11.
//
import Foundation
import GRPCEncapsulates

public struct EventRecord: Sendable {
    /// Unique identifier for this record (must be a valid UUID/GUID).
    /// If not provided, the server will generate a new one.
    public let id: UUID?
    
    /// The record payload as raw bytes.
    /// The format specified in SchemaInfo determines how to interpret these bytes.
    public let data: Data
    
    /// Schema information for this record.
    public let schema: Schema
    
    /// A collection of properties providing additional information about the
    /// record. Can contain user-defined or system propreties.
    /// System keys will be prefixed with "$" (e.g., "$timestamp").
    /// User-defined keys MUST NOT start with "$".
    ///
    /// Common examples:
    ///   User metadata:
    ///     - "user-id": "12345"
    ///     - "tenant": "acme-corp"
    ///     - "source": "mobile-app"
    ///
    ///   System metadata (with $ prefix):
    ///     - "$trace-id": "4bf92f3577b34da6a3ce929d0e0e4736"  // OpenTelemetry trace ID
    ///     - "$span-id": "00f067aa0ba902b7"                   // OpenTelemetry span ID
    ///     - "$timestamp": "2025-01-15T10:30:00.000Z"         // ISO 8601 timestamp
    public var properties: [String: Codable & Sendable]
    
    
    /// Initializes a new event record with an optional identifier, raw payload data,
    /// schema metadata, and associated properties.
    ///
    /// Use this initializer to create a record that can be appended to a stream or
    /// persisted in storage. The `schema` describes how to interpret the raw `data`,
    /// while `properties` carries metadata such as tracing information, timestamps,
    /// or user-defined attributes.
    ///
    /// - Parameters:
    ///   - id: An optional unique identifier (UUID/GUID) for the record. If `nil`,
    ///     the server or storage layer may generate an identifier when the record is
    ///     persisted.
    ///   - data: The raw payload bytes for the record. Interpretation of these bytes
    ///     is defined by the provided `schema`.
    ///   - schema: Schema metadata describing the encoding format (e.g., JSON, Protobuf)
    ///     and logical schema name (and optionally a specific schema/version identifier)
    ///     for the payload data.
    ///   - properties: A dictionary of additional metadata associated with the record.
    ///     Keys prefixed with "$" are reserved for system properties (e.g., "$trace-id",
    ///     "$span-id", "$timestamp"). User-defined keys must not start with "$".
    ///     Values must be `Codable`.
    ///
    /// - Important: Ensure that `schema.format` matches the actual encoding of `data`.
    ///   When using system-reserved properties (keys starting with "$"), avoid collisions
    ///   with user-defined keys.
    ///
    /// - SeeAlso: `EventRecord.SchemaInfo`, `EventRecord.SchemaInfo.SchemaFormat`
    public init(id: UUID? = nil, data: Data, schema: Schema, properties: [String : Codable & Sendable] = [:]) {
        self.id = id
        self.data = data
        self.schema = schema
        self.properties = properties
    }
}

extension EventRecord {    
    /// Convenience initializer to create an EventRecord from a semantic event type, a typed payload,
    /// and optional custom metadata bytes.
    ///
    /// This initializer helps you build an EventRecord without manually assembling SchemaInfo or
    /// encoding metadata dictionaries. It derives the schema format from the provided payload and
    /// attempts to parse custom metadata when present.
    ///
    /// Parameters:
    /// - id: An optional unique identifier (UUID/GUID) for the record. If `nil`, an identifier may be assigned by the server or storage layer.
    /// - eventType: The logical event type or schema name (e.g., "order-placed", "com.acme.orders.placed") used to populate `SchemaInfo.name`.
    /// - payload: The event payload wrapped in `EventRecord.Payload`. Determines both the raw bytes and the schema format (`.json` for JSON models, `.bytes` for raw data).
    /// - customMetadata: Optional raw metadata bytes. When provided, the initializer attempts to parse these bytes as a top-level JSON dictionary and stores the resulting key/value pairs into `properties`.
    ///
    /// Throws:
    /// - An error if JSON encoding of a `.json` payload fails.
    /// - An error if `customMetadata` is provided but cannot be parsed as a top-level JSON dictionary.
    ///
    /// Behavior:
    /// - Builds `SchemaInfo` with `format` inferred from `payload.format` and `name` set to `eventType`.
    /// - If `customMetadata` is non-nil, it is decoded using `JSONSerialization` with `.topLevelDictionaryAssumed` and merged into the record’s `properties`.
    /// - Keys in `customMetadata` that begin with "$" are treated as system-reserved (e.g., "$trace-id", "$span-id", "$timestamp").
    /// - User-defined metadata keys MUST NOT start with "$".
    ///
    /// Usage notes:
    /// - Use `.json` payloads for Codable models to ensure consistent encoding and content typing.
    /// - Provide raw `.data` payloads when you already have serialized bytes (e.g., Protobuf, Avro, or custom binary).
    /// - Ensure that `eventType` is a stable, descriptive schema name to support long-term evolution and interoperability.
    ///
    /// Example:
    /// - JSON model:
    ///   let payload = EventRecord.Payload.json(MyEventModel(...))
    ///   let record = try EventRecord(eventType: "order-placed", payload: payload)
    ///
    /// - Raw bytes with metadata:
    ///   let meta = try JSONSerialization.data(withJSONObject: ["tenant": "acme", "$timestamp": "2026-02-11T10:00:00Z"])
    ///   let payload = EventRecord.Payload.data(binaryBytes, .json) // or appropriate content type
    ///   let record = try EventRecord(eventType: "order-placed", payload: payload, customMetadata: meta)
    public init(id: UUID? = nil, eventType: String, payload: Payload, customMetadata: Data? = nil) throws {
        let schema = Schema(format: payload.format, name: eventType)
        let properties = try customMetadata.flatMap{
            try JSONSerialization.jsonObject(with: $0, options: .topLevelDictionaryAssumed) as? [String: Codable & Sendable]
        } ?? [:]
        try self.init(id: id, data: payload.data, schema: schema, properties: properties)
    }
}

extension EventRecord: Buildable {
    /// OpenTelemetry trace ID
    public func traceId(_ value: String) -> Self{
        return withCopy {
            $0.properties["$trace-id"] = value
        }
    }
    
    /// OpenTelemetry span ID
    public func spanId(_ value: String) -> Self{
        return withCopy {
            $0.properties["$span-id"] = value
        }
    }
    
    /// ISO 8601 timestamp
    public func timestamp(_ value: String) -> Self{
        return withCopy {
            $0.properties["$timestamp"] = value
        }
    }
    
    public func setValue(_ value: Codable & Sendable, forKey key: String)->Self{
        return withCopy {
            $0.properties[key] = value
        }
    }
}

extension EventRecord {
    /// A type-erased container for event payloads that captures both raw bytes and structured JSON models,
    /// along with their corresponding content types.
    ///
    /// Use `Payload` to standardize how event data is represented before encoding and transport.
    /// It ensures that consumers can determine the correct `ContentType` and obtain a `Data` representation
    /// regardless of whether the payload began as raw bytes or a Codable model.
    ///
    /// Cases:
    /// - `data(Data, ContentType)`: Wraps already-encoded bytes with an explicit `ContentType`.
    ///   Use this when you have pre-serialized data (e.g., Protobuf, Avro, custom binary, or JSON you encoded yourself).
    /// - `json(Codable & Sendable)`: Wraps a Codable model that will be JSON-encoded on demand using `JSONEncoder`.
    ///   The associated `contentType` is `.json`.
    ///
    /// Properties:
    /// - `contentType`: The MIME-like content type describing how to interpret the payload.
    ///   - For `.data(_, contentType)`, returns the provided `contentType`.
    ///   - For `.json`, returns `.json`.
    /// - `data`: Lazily produces a `Data` representation of the payload.
    ///   - For `.data(data, _)`, returns the stored bytes.
    ///   - For `.json(model)`, encodes the model using `JSONEncoder`.
    ///   - May throw if JSON encoding fails.
    ///
    /// Thread safety:
    /// - `Payload` is `Sendable` when its associated values are `Sendable`, enabling safe use across tasks.
    ///
    /// Usage notes:
    /// - Prefer `.json` when working with Swift models to avoid manual encoding and to ensure consistent content typing.
    /// - Use `.data` for non-JSON formats or when you have already-encoded bytes and want to retain control of serialization.
    /// - When using `.data` with JSON bytes, set `ContentType.json` to maintain semantic correctness.
    ///
    /// Example:
    /// - JSON model:
    ///   ```swift
    ///   struct Order: Codable, Sendable { let id: String; let total: Double }
    ///   let payload = Payload.json(Order(id: "123", total: 42.0))
    ///   let bytes = try payload.data            // JSON-encoded Data
    ///   let type  = payload.contentType         // .json
    ///   ```
    /// - Raw bytes:
    ///   ```swift
    ///   let protobufBytes: Data = ...
    ///   let payload = Payload.data(protobufBytes, .protobuf)
    ///   let bytes = try payload.data            // returns protobufBytes
    ///   let type  = payload.contentType         // .protobuf
    ///   ```
    public enum Payload: Sendable {
        case data(Data, ContentType)
        case json(Codable & Sendable)

        public var contentType: ContentType {
            switch self {
            case let .data(_, contentType):
                contentType
            case .json:
                .json
            }
        }

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
        
        public var format: Schema.Format{
            get{
                return switch self {
                case .data:
                    .bytes
                case .json:
                    .json
                }
            }
        }
    }
}

extension EventRecord.Schema {
    /// Represents the encoding format of an event record's payload.
    /// 
    /// Use this to indicate how the raw bytes in the associated data should be
    /// interpreted for serialization and deserialization. Choosing the correct
    /// format enables downstream systems to parse, validate, and evolve event
    /// schemas consistently.
    ///
    /// Cases:
    /// - `unspecified`: No explicit format is provided. This should be avoided in
    ///   production as it prevents reliable decoding and validation.
    /// - `json`: The payload is encoded as JSON (typically UTF-8). Suitable for
    ///   human-readable data and broad interoperability. Consider schema evolution
    ///   strategies (e.g., optional fields) when using JSON.
    /// - `protobuf`: The payload is encoded using Protocol Buffers (binary).
    ///   Efficient and strongly-typed with explicit schemas; good for high-throughput
    ///   systems. Requires schema management for compatibility.
    /// - `avro`: The payload is encoded using Apache Avro (binary or JSON).
    ///   Designed for schema evolution and dynamic typing. Common in data pipelines
    ///   and log/event streaming ecosystems.
    /// - `bytes`: The payload is an opaque sequence of bytes with no declared
    ///   higher-level format. Useful for custom or legacy encodings; consumers must
    ///   agree out-of-band on how to interpret the data.
    ///
    /// Notes:
    /// - Prefer specifying a concrete format (`json`, `protobuf`, `avro`) over
    ///   `unspecified` or `bytes` to enable validation and tooling support.
    /// - When using a schema-aware format (`protobuf`, `avro`), pair this with a
    ///   concrete schema identifier/version to support compatibility and evolution.
    /// - The format should match the `SchemaInfo.name` and optional `SchemaInfo.id`
    ///   to ensure consistent interpretation across producers and consumers.
    public enum Format: Int, Sendable {
        case unspecified = 0
        case json        = 1
        case protobuf    = 2
        case avro        = 3
        case bytes       = 4
    }
}


extension EventRecord {
    /// Encapsulates schema metadata for an event record's payload.
    ///
    /// Use `SchemaInfo` to describe how the raw `data` of an event should be
    /// interpreted and validated. It pairs a concrete encoding format with a
    /// human-meaningful schema name and an optional version/identifier, enabling
    /// producers and consumers to evolve and validate payloads consistently.
    ///
    /// Topics:
    /// - Format (`format`): Declares the encoding of the payload (e.g., JSON,
    ///   Protobuf, Avro, or opaque bytes). This informs parsers how to decode the
    ///   raw bytes.
    /// - Name (`name`): Identifies the logical schema (replacing legacy “event
    ///   type”). Common naming strategies include kebab-case (e.g., "order-placed"),
    ///   URNs (e.g., "urn:kurrentdb:events:order-placed:v1"), dotted namespaces
    ///   (e.g., "Orders.OrderPlaced.V2"), or reverse domains
    ///   (e.g., "com.acme.orders.placed").
    /// - Identifier (`id`): Optionally pins to a specific schema version or registry
    ///   identifier, which is useful when enforcing validation and compatibility
    ///   guarantees.
    ///
    /// Recommended usage:
    /// - Prefer specifying a concrete `format` (e.g., `.json`, `.protobuf`, `.avro`)
    ///   over unspecified or raw bytes to enable tooling and validation.
    /// - Choose a stable `name` that conveys the semantic contract of the payload.
    /// - Provide an `id` when integrating with a schema registry or when strict
    ///   versioning and compatibility checks are required.
    ///
    /// Example:
    /// - A JSON payload for an “order placed” event might use:
    ///   - format: `.json`
    ///   - name: "order-placed" or "com.acme.orders.placed"
    ///   - id: "v1" or a registry GUID/URN
    ///
    /// Thread safety:
    /// - `SchemaInfo` is an immutable value type; it is safe to share across
    ///   threads and tasks.
    ///
    /// - Parameters:
    ///   - format: The encoding format used for the payload data.
    ///   - name: The logical schema name describing the payload contract.
    ///   - id: An optional identifier for a specific schema version or registry entry.
    public struct Schema: Sendable {
        /// The format of the data payload.
        /// Determines how the bytes in AppendRecord.data should be interpreted.
        public let format: Format
        
        /// The schema name (replaces the legacy "event type" concept).
        /// Identifies what kind of data this record contains.
        ///
        /// Common naming formats:
        ///   - Kebab-case: "order-placed", "customer-registered"
        ///   - URN format: "urn:kurrentdb:events:order-placed:v1"
        ///   - Dotted namespace: "Teams.Player.V1", "Orders.OrderPlaced.V2"
        ///   - Reverse domain: "com.acme.orders.placed"
        public let name: String
        
        /// The identifier of the specific version of the schema that the record payload
        /// conforms to. This should match a registered schema version in the system.
        /// Not necessary when not enforcing schema validation.
        public let id: String?
        
        public init(format: Format, name: String, id: String? = nil) {
            self.format = format
            self.name = name
            self.id = id
        }
    }
}
