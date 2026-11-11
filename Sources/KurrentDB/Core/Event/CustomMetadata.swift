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

/// Custom metadata written as JSON: any JSON value, nesting arrays and objects at most 64 levels deep.
public struct JSONMetadataFormat: CustomMetadataFormat {
    public init() {}

    public func validate(_ data: Data) throws(KurrentError) {
        do {
            _ = try JSONDecoder().decode(PropertyValue.self, from: data)
        } catch let error as DecodingError {
            throw .decodingError(cause: error)
        } catch {
            throw .internalParsingError(reason: "The custom metadata is not JSON: \(error)")
        }
    }
}

/// Custom metadata as bytes the server stores without reading them. Any bytes are valid.
public struct BytesMetadataFormat: CustomMetadataFormat {
    public init() {}

    public func validate(_: Data) throws(KurrentError) {}
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
    ///   that is not finite.
    public static func json(_ value: some Encodable & Sendable) throws(KurrentError) -> Self {
        let data: Data
        do {
            data = try JSONEncoder().encode(value)
        } catch {
            throw .encodingError(message: "Custom metadata of type \(type(of: value)) cannot be encoded: \(error)", encoding: .utf8)
        }
        return try Self(data: data, format: .json)
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
