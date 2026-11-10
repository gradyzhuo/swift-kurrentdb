//
//  KurrentJSONEncoder.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/11/10.
//

import Foundation

/// Encodes a ``KurrentJSONCodable`` value as JSON the server reads.
///
/// Members are written in the order the type writes them. The result is then read back with
/// ``KurrentJSONDecoder``, as the server would read it, so the same requirements hold for what is
/// written as for what is read, and the output is never an object the server would ignore.
struct KurrentJSONEncoder {
    func encode<T: KurrentJSONCodable>(_ value: T) throws -> Data {
        var container = KurrentJSONEncodingContainer<T.Keys>()
        try value.encode(to: &container)
        let data = Data(container.json)
        // A value the server fails on is refused here: one that does not meet its key's
        // requirement, or a string, at any depth, that reads as a date outside the years 1 to 9999.
        _ = try KurrentJSONDecoder().decode(T.self, from: data)
        return data
    }
}

/// The members of one JSON object being written, through the keys of the type being encoded.
struct KurrentJSONEncodingContainer<Keys: KurrentJSONCodingKey> {
    private var members: [[UInt8]] = []

    /// The object written so far.
    var json: [UInt8] {
        [UInt8(ascii: "{")] + members.joined(separator: [UInt8(ascii: ",")]) + [UInt8(ascii: "}")]
    }

    /// A value the server reads member by member, such as the object under `$acl`.
    mutating func encodeIfPresent<T: KurrentJSONEncodable>(_ value: T?, forKey key: Keys) throws {
        guard let value else {
            return
        }
        var container = KurrentJSONEncodingContainer<T.Keys>()
        try value.encode(to: &container)
        encode(json: container.json, forKey: key)
    }

    /// A plain value, encoded with `JSONEncoder` and written as ``KurrentJSONValue/standardJSON``,
    /// so every string is written the way the server's reader needs it.
    mutating func encodeIfPresent<T: Encodable>(_ value: T?, forKey key: Keys) throws {
        guard let value else {
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var scanner = try KurrentJSONScanner(utf8: encoder.encode(value))
        try encode(json: scanner.scanValue().standardJSON, forKey: key)
    }

    /// JSON a decode kept, or JSON this container produced, written as it is.
    mutating func encode(json: [UInt8], forKey key: Keys) {
        var member: [UInt8] = []
        KurrentJSONValue.write(key.stringValue, to: &member)
        member.append(UInt8(ascii: ":"))
        members.append(member + json)
    }
}
