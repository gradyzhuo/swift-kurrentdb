//
//  KurrentJSONDecoder.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/11/10.
//

import Foundation

/// Decodes a ``KurrentJSONDecodable`` value from JSON as the server reads it.
///
/// Unlike `JSONDecoder`, every occurrence of a repeated key is checked and the last one is read,
/// keys are compared ordinally, an integer is only an Integer token (`60`, not `60.0`), and the
/// text is read with Newtonsoft's syntax; see ``KurrentJSONScanner``.
struct KurrentJSONDecoder {
    func decode<T: KurrentJSONDecodable>(_ type: T.Type, from data: Data) throws -> T {
        var scanner = KurrentJSONScanner(data)
        return try T(from: KurrentJSONDecodingContainer(scanner.scanRootObject()))
    }
}

/// The members of one JSON object, read through the keys of the type being decoded.
struct KurrentJSONDecodingContainer<Keys: KurrentJSONCodingKey> {
    private let members: [KurrentJSONValue.Member]

    /// Checks every occurrence of every member against its key's requirement, as the server checks
    /// each one in turn, including the keys the type never reads.
    init(_ object: KurrentJSONValue) throws {
        guard case let .object(members) = object.token else {
            throw KurrentJSONError("The value must be an object, but is \(object.excerpt).")
        }
        // The server reads this object's tokens itself, and a Comment token is none it expects.
        guard !object.hasComments else {
            throw KurrentJSONError("The object \(object.excerpt) holds a comment between its members, which the server fails on.")
        }
        for member in members {
            // `Keys(stringValue:)` may compare with `String` equality; the server compares ordinally.
            guard let key = Keys(stringValue: member.key), member.isNamed(key.stringValue) else {
                guard !Keys.rejectsUnknownKeys else {
                    throw KurrentJSONError("The key \(member.key) is not one the server reads here.")
                }
                continue
            }
            guard key.requirement.accepts(member.value) else {
                throw KurrentJSONError("The key \(member.key) must hold \(key.requirement.expectation), but holds \(member.value.excerpt).")
            }
        }
        self.members = members
    }

    func contains(_ key: Keys) -> Bool {
        members.contains { $0.isNamed(key.stringValue) }
    }

    /// A value the server reads member by member, such as the object under `$acl`.
    ///
    /// Every occurrence is decoded, so an occurrence a later one replaces is still checked, and
    /// the last one is returned.
    func decodeIfPresent<T: KurrentJSONDecodable>(_ type: T.Type, forKey key: Keys) throws -> T? {
        var last: T?
        for member in members where member.isNamed(key.stringValue) {
            last = try T(from: KurrentJSONDecodingContainer<T.Keys>(member.value))
        }
        return last
    }

    /// A plain value, such as an `Int64` or a `[String]`: the last occurrence, decoded with
    /// `JSONDecoder` from its standard JSON. `init` already checked every occurrence against the
    /// key's requirement, so two occurrences may differ in form, such as a string and an array.
    func decodeIfPresent<T: Decodable>(_ type: T.Type, forKey key: Keys) throws -> T? {
        guard let member = members.last(where: { $0.isNamed(key.stringValue) }) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(type, from: Data(member.value.standardJSON))
        } catch {
            throw KurrentJSONError("The key \(member.key) does not decode as \(type): \(error)")
        }
    }

    /// The members whose key `isIncluded` accepts: the last occurrence of each key, where it
    /// stands, with its value rewritten as ``KurrentJSONValue/standardJSON``.
    func members(where isIncluded: (Keys) -> Bool) -> [(key: String, json: [UInt8])] {
        members.lastOccurrences.compactMap { member in
            guard let key = Keys(stringValue: member.key), isIncluded(key) else {
                return nil
            }
            return (member.key, member.value.standardJSON)
        }
    }
}
