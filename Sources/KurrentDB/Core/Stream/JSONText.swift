//
//  JSONText.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/11/3.
//

import Foundation

/// A JSON text as a token reader sees it: every member of every object in order, a repeated key
/// included, and every value as the token it is written as.
///
/// The server reads stream metadata with Newtonsoft.Json's token reader: it checks each member as
/// it comes, so an invalid occurrence of a repeated key rejects the object, and otherwise the
/// last occurrence wins. `JSONDecoder` keeps the first occurrence and hands over values, not
/// tokens (`60`, `60.0` and `6e1` decode alike), so ``StreamMetadata`` checks the members here
/// and rewrites the text to the occurrences the server applies.
///
/// Keys are compared by their Unicode scalars, after escapes are resolved, as the server compares
/// them: `"café"` written precomposed and decomposed are two keys, although Swift's `String`
/// compares them equal.
struct JSONText {
    /// An object member.
    struct Member {
        /// The key with its escapes resolved, as UTF-8: two keys are the same key when these
        /// bytes are, that is, when their Unicode scalars are.
        let name: [UInt8]
        /// The key as written, quotes included.
        let quotedName: ArraySlice<UInt8>
        let value: Value

        /// Whether the key is `key`, scalar for scalar.
        func isNamed(_ key: String) -> Bool {
            name.elementsEqual(key.utf8)
        }
    }

    /// A scanned value: the token it starts with, its bytes in the input, and its rewritten bytes
    /// when an object in it repeats a key.
    struct Value {
        enum Token {
            case object([Member])
            case array([Value])
            case string
            case number
            case bool
            case null
        }

        let token: Token
        let text: ArraySlice<UInt8>
        let rewritten: [UInt8]?

        /// The number when it is written as an integer token that fits in `Int64`, as the server
        /// reads a `long`: no fraction and no exponent, so `60.0` and `6e1` are not integers.
        var integer: Int64? {
            guard case .number = token,
                  !text.contains(where: { $0 == UInt8(ascii: ".") || $0 == UInt8(ascii: "e") || $0 == UInt8(ascii: "E") })
            else {
                return nil
            }
            return Int64(String(decoding: text, as: UTF8.self))
        }

        /// The text, shortened to `limit` bytes for an error message.
        func excerpt(limit: Int = 40) -> String {
            let excerpt = String(decoding: text.prefix(limit), as: UTF8.self)
            return text.count > limit ? excerpt + "…" : excerpt
        }
    }

    /// The top-level value.
    let root: Value

    /// Scans `data`; `nil` if it is not a well-formed JSON text.
    ///
    /// `data` must be JSON that `JSONDecoder` has accepted, so it nests at most
    /// ``PropertyValue/maximumDepth`` levels deep, which bounds the recursion here. Like
    /// `JSONDecoder`, the scan skips a leading UTF-8 byte order mark and accepts one trailing comma
    /// after the last member of an object or the last element of an array, as the server does.
    init?(_ data: Data) {
        var scanner = Scanner(bytes: Array(data))
        if scanner.bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            scanner.index = 3
        }
        guard let root = scanner.value(), scanner.isAtEnd() else {
            return nil
        }
        self.root = root
    }

    /// The text with each object holding only the last occurrence of every key it repeats, or
    /// `nil` when no object repeats a key, which is the common case.
    ///
    /// Members keep their order; a repeated key sits where its last occurrence was.
    var keepingLastOccurrences: Data? {
        root.rewritten.map { Data($0) }
    }

    /// Whether `data` is UTF-8 without a NUL byte, as a JSON text the server stores must be.
    ///
    /// `JSONDecoder` also reads UTF-16 and UTF-32. Their byte order marks are not UTF-8, and text in
    /// them without one holds NUL bytes, which a UTF-8 JSON text never does: a control character
    /// in a string must be escaped.
    static func isUTF8(_ data: Data) -> Bool {
        !data.contains(0) && String(validating: data, as: UTF8.self) != nil
    }
}

private struct Scanner {
    let bytes: [UInt8]
    var index = 0

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    /// Whether only whitespace is left.
    mutating func isAtEnd() -> Bool {
        skipWhitespace()
        return index == bytes.count
    }

    /// The value at `index`, after any whitespace; `nil` if the text is not well formed.
    mutating func value() -> JSONText.Value? {
        skipWhitespace()
        guard index < bytes.count else { return nil }
        let start = index
        let token: JSONText.Value.Token
        switch bytes[index] {
        case UInt8(ascii: "{"):
            return object()
        case UInt8(ascii: "["):
            return array()
        case UInt8(ascii: "\""):
            guard string() else { return nil }
            token = .string
        default:
            // A number, `true`, `false` or `null`: everything up to the next delimiter.
            while index < bytes.count, !Self.isDelimiter(bytes[index]) {
                index += 1
            }
            switch bytes[start ..< index] {
            case ArraySlice("true".utf8), ArraySlice("false".utf8):
                token = .bool
            case ArraySlice("null".utf8):
                token = .null
            case let text where text.first == UInt8(ascii: "-") || text.first.map(Self.isDigit) == true:
                token = .number
            default:
                return nil
            }
        }
        return .init(token: token, text: bytes[start ..< index], rewritten: nil)
    }

    private mutating func object() -> JSONText.Value? {
        let start = index
        index += 1
        var members: [JSONText.Member] = []
        skipWhitespace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "}") {
            index += 1
            return .init(token: .object([]), text: bytes[start ..< index], rewritten: nil)
        }
        while true {
            skipWhitespace()
            let keyStart = index
            guard index < bytes.count, bytes[index] == UInt8(ascii: "\""), string() else { return nil }
            let quotedName = bytes[keyStart ..< index]
            guard let name = Self.name(quotedName) else { return nil }
            skipWhitespace()
            guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { return nil }
            index += 1
            guard let value = value() else { return nil }
            members.append(.init(name: name, quotedName: quotedName, value: value))
            guard let end = endOfMember(closingWith: "}") else { return nil }
            if end { break }
        }

        let text = bytes[start ..< index]
        var lastOccurrence: [[UInt8]: Int] = [:]
        for (offset, member) in members.enumerated() {
            lastOccurrence[member.name] = offset
        }
        guard lastOccurrence.count < members.count || members.contains(where: { $0.value.rewritten != nil }) else {
            return .init(token: .object(members), text: text, rewritten: nil)
        }
        var rewritten: [UInt8] = [UInt8(ascii: "{")]
        for (offset, member) in members.enumerated() where lastOccurrence[member.name] == offset {
            if rewritten.count > 1 {
                rewritten.append(UInt8(ascii: ","))
            }
            rewritten += member.quotedName
            rewritten.append(UInt8(ascii: ":"))
            rewritten += member.value.rewritten ?? Array(member.value.text)
        }
        rewritten.append(UInt8(ascii: "}"))
        return .init(token: .object(members), text: text, rewritten: rewritten)
    }

    private mutating func array() -> JSONText.Value? {
        let start = index
        index += 1
        var elements: [JSONText.Value] = []
        skipWhitespace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "]") {
            index += 1
            return .init(token: .array([]), text: bytes[start ..< index], rewritten: nil)
        }
        while true {
            guard let element = value() else { return nil }
            elements.append(element)
            guard let end = endOfMember(closingWith: "]") else { return nil }
            if end { break }
        }

        let text = bytes[start ..< index]
        guard elements.contains(where: { $0.rewritten != nil }) else {
            return .init(token: .array(elements), text: text, rewritten: nil)
        }
        var rewritten: [UInt8] = [UInt8(ascii: "[")]
        for (offset, element) in elements.enumerated() {
            if offset > 0 {
                rewritten.append(UInt8(ascii: ","))
            }
            rewritten += element.rewritten ?? Array(element.text)
        }
        rewritten.append(UInt8(ascii: "]"))
        return .init(token: .array(elements), text: text, rewritten: rewritten)
    }

    /// Consumes the `,` or the closing bracket after a member: `false` after a comma, `true` after
    /// the closing bracket, including one after a trailing comma, `nil` for anything else.
    private mutating func endOfMember(closingWith closing: Unicode.Scalar) -> Bool? {
        skipWhitespace()
        guard index < bytes.count else { return nil }
        switch bytes[index] {
        case UInt8(ascii: ","):
            index += 1
            skipWhitespace()
            guard index < bytes.count, bytes[index] == UInt8(ascii: closing) else {
                return false
            }
            index += 1
            return true
        case UInt8(ascii: closing):
            index += 1
            return true
        default:
            return nil
        }
    }

    /// Consumes the string starting at `index`, its quotes included; `false` if it does not end.
    private mutating func string() -> Bool {
        index += 1
        while index < bytes.count {
            switch bytes[index] {
            case UInt8(ascii: "\\"):
                index += 2
            case UInt8(ascii: "\""):
                index += 1
                return true
            default:
                index += 1
            }
        }
        return false
    }

    private mutating func skipWhitespace() {
        while index < bytes.count, Self.isWhitespace(bytes[index]) {
            index += 1
        }
    }

    /// The key a quoted JSON string denotes, its escapes resolved, as UTF-8, so `"$maxCount"`
    /// and `"$maxCount"` are the same key; `nil` if an escape is invalid. A `String` keeps every
    /// Unicode scalar as decoded, so its UTF-8 is exact.
    private static func name(_ quoted: ArraySlice<UInt8>) -> [UInt8]? {
        guard quoted.contains(UInt8(ascii: "\\")) else {
            return Array(quoted.dropFirst().dropLast())
        }
        return (try? JSONDecoder().decode(String.self, from: Data(quoted))).map { Array($0.utf8) }
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") || byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r")
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(byte)
    }

    private static func isDelimiter(_ byte: UInt8) -> Bool {
        isWhitespace(byte) || byte == UInt8(ascii: ",") || byte == UInt8(ascii: "]") || byte == UInt8(ascii: "}")
    }
}
