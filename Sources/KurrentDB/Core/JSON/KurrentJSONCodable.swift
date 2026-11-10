//
//  KurrentJSONCodable.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/11/10.
//

/// A value the server reads with its own JSON rules, such as stream metadata.
///
/// Not `Decodable`: only ``KurrentJSONDecoder`` creates it, so `JSONDecoder`, which reads the
/// first occurrence of a repeated key and `60.0` as the integer 60, cannot.
protocol KurrentJSONDecodable {
    associatedtype Keys: KurrentJSONCodingKey
    init(from container: KurrentJSONDecodingContainer<Keys>) throws
}

/// A value written as the server reads it. Not `Encodable`: only ``KurrentJSONEncoder`` writes it.
protocol KurrentJSONEncodable {
    associatedtype Keys: KurrentJSONCodingKey
    func encode(to container: inout KurrentJSONEncodingContainer<Keys>) throws
}

typealias KurrentJSONCodable = KurrentJSONDecodable & KurrentJSONEncodable

/// The keys of a ``KurrentJSONDecodable`` type, each with the token the server requires under it:
/// the `switch (name)` of the server's reader.
protocol KurrentJSONCodingKey: CodingKey {
    /// What the server requires of the value under this key, at every occurrence of the key.
    var requirement: KurrentJSONRequirement { get }
    /// Whether the server fails on a key it does not know, as its `$acl` reader does.
    static var rejectsUnknownKeys: Bool { get }
}

/// The token the server's reader requires under a key.
indirect enum KurrentJSONRequirement: Sendable {
    /// A value the server skips with `JToken.ReadFrom`.
    case any
    /// `Check(JsonToken.Integer)` and a cast to `long`, within the range the server then accepts.
    case integer(ClosedRange<Int64>)
    /// `Check(JsonToken.Boolean)`.
    case boolean
    /// `Check(JsonToken.String)`: a string Newtonsoft does not read as a Date token.
    case string
    /// An object the server reads member by member, through the type decoded under the key.
    case object
    case array(of: KurrentJSONRequirement)
    case either(KurrentJSONRequirement, KurrentJSONRequirement)

    /// Whether the server's reader accepts `value` under a key with this requirement.
    func accepts(_ value: KurrentJSONValue) -> Bool {
        switch (self, value.token) {
        case (.any, _):
            true
        case let (.integer(range), .number(number)):
            // The scanner classified the token: a Float token has no `integer`.
            number.integer.map(range.contains) == true
        case (.boolean, .bool):
            true
        case let (.string, .string(_, isDate)):
            !isDate
        case (.object, .object):
            true
        case let (.array(element), .array(values)):
            // The server reads the elements itself, so a comment between them fails.
            !value.hasComments && values.allSatisfy(element.accepts)
        case let (.either(first, second), _):
            first.accepts(value) || second.accepts(value)
        default:
            false
        }
    }

    /// What a value must be, for an error message.
    var expectation: String {
        switch self {
        case .any:
            "any value"
        case let .integer(range):
            "an integer from \(range.lowerBound) to \(range.upperBound), written without a fraction or an exponent"
        case .boolean:
            "a boolean"
        case .string:
            "a string that does not read as a date"
        case .object:
            "an object"
        case let .array(element):
            "an array of \(element.expectation), without comments"
        case let .either(first, second):
            "\(first.expectation) or \(second.expectation)"
        }
    }
}
