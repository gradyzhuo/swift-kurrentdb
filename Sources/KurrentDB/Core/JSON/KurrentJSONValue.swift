//
//  KurrentJSONValue.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/11/10.
//

import Foundation

/// One JSON value as the server's token reader (Newtonsoft.Json's `JsonTextReader`) reads it.
///
/// The tree exists only while ``KurrentJSONDecoder`` decodes: it holds every occurrence of a
/// repeated key, in order, and every value as the token it is, so a type can be checked member by
/// member as the server checks it. What a type keeps afterwards is its own fields.
struct KurrentJSONValue {
    indirect enum Token {
        /// Every member, a repeated key included, in order.
        case object([Member])
        case array([KurrentJSONValue])
        /// `new Name(arguments)`, which Newtonsoft reads as a constructor.
        case constructor(name: String, arguments: [KurrentJSONValue])
        /// The string with its escapes resolved. `isDate` when Newtonsoft reads it as a Date token.
        case string(String, isDate: Bool)
        case number(Number)
        case bool(Bool)
        case null
        /// `undefined`, or the value Newtonsoft reads where a comma stands in place of one.
        case undefined
    }

    struct Number {
        /// The value of an Integer token Newtonsoft holds as an `Int64`: `60`, `010` (8), `0x10`
        /// (16). `nil` for a Float token such as `60.0`, `6e1` or `NaN`, and for an integer
        /// Newtonsoft holds as a `BigInteger`, which the server cannot cast to a `long`.
        let integer: Int64?
        /// The number in standard JSON, every digit kept: `.5` as `0.5`, `010` as `8`. `NaN`,
        /// `Infinity` and `-Infinity` have no JSON form and stay as they are.
        let text: String
    }

    struct Member {
        /// The key with its escapes resolved. Compare it by `utf8`, never with `==`: the server
        /// compares keys ordinally, and `String` equality merges canonically equivalent spellings.
        let key: String
        let value: KurrentJSONValue

        func isNamed(_ name: String) -> Bool {
            key.utf8.elementsEqual(name.utf8)
        }
    }

    let token: Token
    /// Whether a comment stands directly inside this object, array or constructor. Newtonsoft
    /// hands a comment over as a token: the server's own reader fails on it, and only a value it
    /// skips with `JToken.ReadFrom` may hold one inside.
    let hasComments: Bool
    /// The value as written, for error messages.
    let source: ArraySlice<UInt16>

    init(_ token: Token, hasComments: Bool = false, source: ArraySlice<UInt16>) {
        self.token = token
        self.hasComments = hasComments
        self.source = source
    }

    /// The start of the value as written, for an error message.
    var excerpt: String {
        let limit = 60
        let text = String(decoding: source.prefix(limit), as: UTF16.self)
        return source.count > limit ? text + "…" : text
    }
}

extension KurrentJSONValue {
    /// The value rewritten as standard JSON: the last occurrence of each repeated key, where that
    /// occurrence stands, strings and keys re-escaped, comments dropped, numbers as
    /// ``Number/text``. Only `NaN`, `Infinity`, `-Infinity`, `undefined` and constructors, which
    /// JSON cannot express, stay as Newtonsoft reads them.
    var standardJSON: [UInt8] {
        var bytes: [UInt8] = []
        write(to: &bytes)
        return bytes
    }

    private func write(to bytes: inout [UInt8]) {
        switch token {
        case let .object(members):
            bytes.append(UInt8(ascii: "{"))
            for (index, member) in members.lastOccurrences.enumerated() {
                if index > 0 {
                    bytes.append(UInt8(ascii: ","))
                }
                Self.write(member.key, to: &bytes)
                bytes.append(UInt8(ascii: ":"))
                member.value.write(to: &bytes)
            }
            bytes.append(UInt8(ascii: "}"))
        case let .array(elements):
            bytes.append(UInt8(ascii: "["))
            Self.write(elements, to: &bytes)
            bytes.append(UInt8(ascii: "]"))
        case let .constructor(name, arguments):
            bytes.append(contentsOf: "new \(name)(".utf8)
            Self.write(arguments, to: &bytes)
            bytes.append(UInt8(ascii: ")"))
        case let .string(text, _):
            Self.write(text, to: &bytes)
        case let .number(number):
            bytes.append(contentsOf: number.text.utf8)
        case let .bool(value):
            bytes.append(contentsOf: (value ? "true" : "false").utf8)
        case .null:
            bytes.append(contentsOf: "null".utf8)
        case .undefined:
            bytes.append(contentsOf: "undefined".utf8)
        }
    }

    private static func write(_ elements: [KurrentJSONValue], to bytes: inout [UInt8]) {
        for (index, element) in elements.enumerated() {
            if index > 0 {
                bytes.append(UInt8(ascii: ","))
            }
            element.write(to: &bytes)
        }
    }

    /// `text` as a JSON string: quotes, backslashes and control characters escaped, the rest as UTF-8.
    ///
    /// A string starting with `/Date(` gets its first slash escaped. Newtonsoft decides whether
    /// such a string is a date partly from where it stands in the reader's buffer (see
    /// ``NewtonsoftDate/classify(_:bufferIndex:)``); an escape makes the reader copy the string, so
    /// it is read the same way wherever it is written.
    static func write(_ text: String, to bytes: inout [UInt8]) {
        bytes.append(UInt8(ascii: "\""))
        if text.utf8.starts(with: "/Date(".utf8) {
            bytes.append(UInt8(ascii: "\\"))
        }
        for byte in text.utf8 {
            switch byte {
            case UInt8(ascii: "\""), UInt8(ascii: "\\"):
                bytes.append(UInt8(ascii: "\\"))
                bytes.append(byte)
            case 0 ..< 0x20:
                let hex = Array("0123456789abcdef".utf8)
                bytes.append(contentsOf: [UInt8(ascii: "\\"), UInt8(ascii: "u"), UInt8(ascii: "0"), UInt8(ascii: "0"), hex[Int(byte >> 4)], hex[Int(byte & 0xF)]])
            default:
                bytes.append(byte)
            }
        }
        bytes.append(UInt8(ascii: "\""))
    }
}

extension KurrentJSONValue {
    /// What stands in the value that JSON cannot express and `JSONDecoder` therefore cannot read:
    /// `NaN`, `Infinity`, `-Infinity`, `undefined` or a constructor. `nil` for standard JSON.
    var nonStandardToken: String? {
        switch token {
        case let .object(members):
            members.lazy.compactMap(\.value.nonStandardToken).first
        case let .array(elements):
            elements.lazy.compactMap(\.nonStandardToken).first
        case let .constructor(name, _):
            "new \(name)(…)"
        case let .number(number):
            // Every other number is made of digits, a sign, a point and an `e`.
            number.text.utf8.contains { $0 == UInt8(ascii: "N") || $0 == UInt8(ascii: "I") } ? number.text : nil
        case .undefined:
            "undefined"
        case .string, .bool, .null:
            nil
        }
    }
}

extension [KurrentJSONValue.Member] {
    /// The last occurrence of each key, where it stands. Keys are compared by their UTF-8 bytes,
    /// as the server compares them, in one pass.
    var lastOccurrences: [KurrentJSONValue.Member] {
        var lastIndex: [[UInt8]: Int] = [:]
        for (index, member) in enumerated() {
            lastIndex[[UInt8](member.key.utf8)] = index
        }
        guard lastIndex.count < count else {
            return self
        }
        return enumerated().filter { lastIndex[[UInt8]($0.element.key.utf8)] == $0.offset }.map(\.element)
    }
}

/// Why ``KurrentJSONDecoder`` or ``KurrentJSONEncoder`` refuses a value: the server would ignore
/// the whole object for it.
struct KurrentJSONError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
