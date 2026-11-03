//
//  PropertyValue.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/11/2.
//
import Foundation
import SwiftProtobuf

/// A record property as a JSON value, the form both append paths send it in.
///
/// AppendRecords and AppendSession carry properties as `google.protobuf.Value`; BatchAppend carries
/// them as the JSON bytes of the event's custom metadata. Every property is normalised to this
/// value first, so neither path drops or nulls a value it does not recognise.
///
/// Decoding goes through `JSONDecoder` rather than `JSONSerialization`, so a boolean and a number
/// are told apart the same way on every platform, without inspecting `NSNumber`. A number is kept
/// as the integer it equals when it is whole and fits in `Int64` or `UInt64`, whether written as
/// `3` or `3e0`, and as a `Double` otherwise, so the JSON BatchAppend sends holds the same integer;
/// a number with a fraction keeps the precision of a `Double`.
///
/// A `google.protobuf.Value` number is a `Double`, so AppendRecords and AppendSession send the
/// `Double` nearest to each number: an integer beyond ±2^53 arrives rounded, as it does from
/// every KurrentDB client. Store such a value as a string to keep every digit.
///
/// A decoded text may nest arrays and objects at most ``maximumDepth`` (64) levels deep; a deeper
/// one throws `DecodingError.dataCorrupted` instead of overflowing the stack.
package enum PropertyValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case integer(Int64)
    case unsignedInteger(UInt64)
    case double(Double)
    case string(String)
    case array([PropertyValue])
    case object([String: PropertyValue])
}

extension PropertyValue: Codable {
    package init(from decoder: any Swift.Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self), Self.denotes(Decimal(value), container) {
            self = .integer(value)
        } else if let value = try? container.decode(UInt64.self), Self.denotes(Decimal(value), container) {
            self = .unsignedInteger(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            // Decoding recurses once per array or object, and a text nested a few hundred levels deep
            // overflows the stack before JSONDecoder's own limit of 512 levels. Refuse the level past
            // the limit before descending into it. A container at `codingPath.count` n is level n + 1.
            guard decoder.codingPath.count < Self.maximumDepth else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "The JSON nests arrays and objects more than \(Self.maximumDepth) levels deep."
                ))
            }
            do {
                self = try .array(container.decode([PropertyValue].self))
            } catch DecodingError.typeMismatch {
                self = try .object(container.decode([String: PropertyValue].self))
            }
        }
    }

    /// The deepest nesting of arrays and objects a decoded JSON text may have: 64 levels, the
    /// outermost array or object being the first. A deeper text throws `DecodingError.dataCorrupted`.
    package static let maximumDepth = 64

    /// Whether the number in `container` is exactly `integer`.
    ///
    /// Decoding an integer type truncates a fraction (`9007199254740993.5` decodes as an `Int64`),
    /// so the integer is checked against the `Decimal` the token denotes.
    private static func denotes(_ integer: Decimal, _ container: any SingleValueDecodingContainer) -> Bool {
        (try? container.decode(Decimal.self)) == integer
    }

    package func encode(to encoder: any Swift.Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case let .bool(value):
            try container.encode(value)
        case let .integer(value):
            try container.encode(value)
        case let .unsignedInteger(value):
            try container.encode(value)
        case let .double(value):
            try container.encode(value)
        case let .string(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        }
    }
}

extension PropertyValue {
    /// Normalises a property value set on an ``EventRecord``.
    ///
    /// Strings, booleans, integers and floating-point numbers map directly; any other `Codable`
    /// value (a `Date`, a nested struct, an optional) is encoded with a default `JSONEncoder` and
    /// read back as JSON.
    ///
    /// - Throws: `EncodingError` when an integer does not fit in 64 bits, when a number is NaN or
    ///   infinite (neither JSON nor `google.protobuf.Value` can carry it), or when the value cannot
    ///   be JSON-encoded.
    package init(_ value: any Codable & Sendable) throws {
        switch value {
        case let value as PropertyValue:
            self = value
        case let value as String:
            self = .string(value)
        case let value as Bool:
            self = .bool(value)
        case let value as any BinaryInteger:
            if let integer = Int64(exactly: value) {
                self = .integer(integer)
            } else if let integer = UInt64(exactly: value) {
                self = .unsignedInteger(integer)
            } else {
                throw EncodingError.invalidValue(value, .init(
                    codingPath: [],
                    debugDescription: "The integer \(value) does not fit in 64 bits."
                ))
            }
        case let value as Double:
            self = try .finite(value)
        case let value as Float:
            self = try .finite(Double(value))
        default:
            let data = try JSONEncoder().encode(value)
            self = try JSONDecoder().decode(PropertyValue.self, from: data)
        }
    }

    private static func finite(_ value: Double) throws -> PropertyValue {
        guard value.isFinite else {
            throw EncodingError.invalidValue(value, .init(
                codingPath: [],
                debugDescription: "\(value) is not a finite number, which JSON and google.protobuf.Value cannot carry."
            ))
        }
        return .double(value)
    }

    /// The scalar as a plain Swift value, or the value itself for null, arrays and objects.
    ///
    /// Used for the properties parsed from custom metadata, so that a caller reading
    /// `record.properties["key"]` back can cast a string, boolean or number as usual.
    var unwrapped: any Codable & Sendable {
        switch self {
        case let .bool(value): value
        case let .integer(value): Int(exactly: value).map { $0 as any Codable & Sendable } ?? value
        case let .unsignedInteger(value): value
        case let .double(value): value
        case let .string(value): value
        case .null, .array, .object: self
        }
    }

    /// The value as a `google.protobuf.Value`, which carries every number as the nearest `Double`.
    package var protobufValue: Google_Protobuf_Value {
        switch self {
        case .null:
            .init(nilLiteral: ())
        case let .bool(value):
            .init(boolValue: value)
        case let .integer(value):
            .init(numberValue: Double(value))
        case let .unsignedInteger(value):
            .init(numberValue: Double(value))
        case let .double(value):
            .init(numberValue: value)
        case let .string(value):
            .init(stringValue: value)
        case let .array(values):
            .init(listValue: .init(values: values.map(\.protobufValue)))
        case let .object(fields):
            .init(structValue: .init(fields: fields.mapValues(\.protobufValue)))
        }
    }
}

extension EventRecord {
    /// The record's properties normalised to JSON values.
    package func normalizedProperties() throws -> [String: PropertyValue] {
        try properties.mapValues { try PropertyValue($0) }
    }

    /// The record's properties as the `google.protobuf.Value` map AppendRecords and AppendSession send.
    ///
    /// - Throws: ``KurrentError/encodingError(message:encoding:)`` when a property cannot be encoded.
    package func protobufProperties() throws(KurrentError) -> [String: Google_Protobuf_Value] {
        do {
            return try normalizedProperties().mapValues(\.protobufValue)
        } catch {
            throw .encodingError(message: "the properties of record of type '\(schema.name)' cannot be encoded: \(error)", encoding: .utf8)
        }
    }

    /// The record's properties as the JSON custom metadata BatchAppend sends, or `nil` when there are none.
    ///
    /// - Throws: ``KurrentError/encodingError(message:encoding:)`` when a property cannot be encoded.
    package func customMetadataJSON() throws(KurrentError) -> Data? {
        guard !properties.isEmpty else { return nil }
        do {
            return try JSONEncoder().encode(normalizedProperties())
        } catch {
            throw .encodingError(message: "the properties of record of type '\(schema.name)' cannot be encoded: \(error)", encoding: .utf8)
        }
    }
}
