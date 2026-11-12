//
//  CustomMetadata.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/11/11.
//

import Foundation

/// How the bytes of an event's custom metadata are written, and the rule they must follow.
///
/// A format is a value, so one that needs parameters can carry them. `validate(_:)` has no default
/// implementation: every format states its own rule.
public protocol CustomMetadataFormat: Sendable, Equatable {
    /// Checks that `data` is written in this format.
    ///
    /// - Throws: `KurrentError` when it is not.
    func validate(_ data: Data) throws(KurrentError)
}

/// Custom metadata written as JSON: a value `JSONDecoder` reads, nesting arrays and objects at
/// most 64 levels deep.
public struct JSONMetadataFormat: CustomMetadataFormat {
    public init() {}

    /// Any JSON value, as `JSONDecoder` reads it: every scalar is decoded, a number as a `Double`.
    private struct AnyValue: Decodable {
        init(from decoder: any Decoder) throws {
            let scalar = try decoder.singleValueContainer()
            if scalar.decodeNil()
                || (try? scalar.decode(Bool.self)) != nil
                || (try? scalar.decode(Double.self)) != nil
                || (try? scalar.decode(String.self)) != nil
            {
                return
            }
            // Only arrays and objects count as levels. A container at `codingPath.count` n is level n + 1.
            var elements: (any UnkeyedDecodingContainer)?
            var members: KeyedDecodingContainer<Key>?
            do {
                elements = try decoder.unkeyedContainer()
            } catch {
                // Not an array: an object, or a scalar JSONDecoder refuses, which this rethrows.
                members = try decoder.container(keyedBy: Key.self)
            }
            guard decoder.codingPath.count < PropertyValue.maximumDepth else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "The JSON nests arrays and objects more than \(PropertyValue.maximumDepth) levels deep."
                ))
            }
            if var elements {
                while !elements.isAtEnd {
                    _ = try elements.decode(AnyValue.self)
                }
            } else if let members {
                for key in members.allKeys {
                    _ = try members.decode(AnyValue.self, forKey: key)
                }
            }
        }

        struct Key: CodingKey {
            let stringValue: String
            let intValue: Int? = nil
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue _: Int) { nil }
        }
    }

    public func validate(_ data: Data) throws(KurrentError) {
        do {
            _ = try JSONDecoder().decode(AnyValue.self, from: data)
        } catch let error as DecodingError {
            throw .decodingError(cause: error)
        } catch {
            throw .internalParsingError(reason: "The custom metadata is not JSON: \(error)")
        }
    }
}

/// Custom metadata as bytes the server stores without reading them. Any bytes are valid, except
/// none: an event stored with empty metadata reads back as an event without metadata.
public struct BytesMetadataFormat: CustomMetadataFormat {
    public init() {}

    public func validate(_ data: Data) throws(KurrentError) {
        guard !data.isEmpty else {
            throw .initializationError(reason: "Custom metadata cannot be empty: it would read back as no metadata. Leave the argument out for an event without metadata.")
        }
    }
}

extension CustomMetadataFormat where Self == JSONMetadataFormat {
    /// JSON. See ``JSONMetadataFormat``.
    public static var json: Self { .init() }
}

extension CustomMetadataFormat where Self == BytesMetadataFormat {
    /// Bytes stored as they are. See ``BytesMetadataFormat``.
    public static var bytes: Self { .init() }
}

/// A format ``EventData`` accepts for its custom metadata: JSON or bytes.
public protocol EventDataMetadataFormat: CustomMetadataFormat {}

/// A format ``EventRecord`` accepts for its custom metadata: JSON only, since a record's metadata
/// is sent as key-value properties.
public protocol EventRecordMetadataFormat: CustomMetadataFormat {}

extension JSONMetadataFormat: EventDataMetadataFormat, EventRecordMetadataFormat {}
extension BytesMetadataFormat: EventDataMetadataFormat {}

/// The custom metadata of an event: its bytes and the format they are written in.
///
/// The keys are yours: encode your own `Encodable` type and decode it back.
///
/// ```swift
/// struct OrderMetadata: Codable, Sendable {
///     var tenant: String
///     var operatorId: String
/// }
///
/// let event = EventData(
///     eventType: "OrderPlaced",
///     payload: .json(["orderId": "123"]),
///     customMetadata: try .json(OrderMetadata(tenant: "acme", operatorId: "op-7"))
/// )
/// ```
///
/// The format is not stored on the server, so a reader names it:
/// ``RecordedEvent/customMetadata(format:)``.
public struct CustomMetadata<Format: CustomMetadataFormat>: Sendable, Equatable {
    /// The bytes as they are stored.
    public let data: Data

    /// The format `data` is written in.
    public let format: Format

    /// Creates custom metadata from bytes already written in `format`.
    ///
    /// - Throws: `KurrentError` when `data` is not valid in `format`.
    public init(data: Data, format: Format) throws(KurrentError) {
        try format.validate(data)
        self.data = data
        self.format = format
    }
}

extension CustomMetadata where Format == JSONMetadataFormat {
    /// Encodes `value` as JSON with `JSONEncoder`'s default strategies.
    ///
    /// - Throws: `KurrentError.encodingError` when `value` cannot be encoded, such as a `Double`
    ///   that is not finite, or encodes to JSON nested more than 64 levels deep.
    public static func json(_ value: some Encodable & Sendable) throws(KurrentError) -> Self {
        let data: Data
        do {
            data = try JSONEncoder().encode(value)
        } catch {
            throw .encodingError(message: "Custom metadata of type \(type(of: value)) cannot be encoded: \(error)", encoding: .utf8)
        }
        do {
            return try Self(data: data, format: .json)
        } catch {
            throw .encodingError(message: "Custom metadata of type \(type(of: value)) cannot be stored: \(error)", encoding: .utf8)
        }
    }

    /// Decodes the JSON into `type`. Members `type` does not declare are ignored.
    ///
    /// - Throws: `KurrentError.decodingError` when the JSON does not decode as `type`.
    public func decode<T: Decodable>(_ type: T.Type) throws(KurrentError) -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch let error as DecodingError {
            throw .decodingError(cause: error)
        } catch {
            throw .internalParsingError(reason: "The custom metadata does not decode as \(type): \(error)")
        }
    }
}

extension RecordedEvent {
    /// The event's custom metadata, read as `format`, or `nil` when the event has none.
    ///
    /// The server keeps no difference between empty metadata and none, so `nil` is also what an
    /// event stored with empty metadata reads as. ``CustomMetadata`` refuses empty bytes for that
    /// reason.
    ///
    /// ```swift
    /// struct OrderMetadata: Codable, Sendable {
    ///     var tenant: String
    /// }
    ///
    /// for try await response in client.streams(specified: "orders").read() {
    ///     let recorded = try response.event.record
    ///     if let metadata = try recorded.customMetadata(format: .json)?.decode(OrderMetadata.self) {
    ///         print(metadata.tenant)
    ///     }
    ///     if let bytes = try recorded.customMetadata(format: .bytes)?.data {
    ///         print(bytes.count)
    ///     }
    /// }
    /// ```
    ///
    /// - Throws: `KurrentError` when the stored bytes are not valid in `format`.
    public func customMetadata<Format: CustomMetadataFormat>(format: Format) throws(KurrentError) -> CustomMetadata<Format>? {
        guard !customMetadata.isEmpty else {
            return nil
        }
        return try CustomMetadata(data: customMetadata, format: format)
    }
}
