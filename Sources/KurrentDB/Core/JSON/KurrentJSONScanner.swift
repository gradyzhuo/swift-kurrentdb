//
//  KurrentJSONScanner.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/11/10.
//

import Foundation

/// Reads JSON text into a ``KurrentJSONValue`` as the server reads stream metadata.
///
/// The server hands the bytes to a .NET `StreamReader` and reads tokens with Newtonsoft.Json's
/// `JsonTextReader`. This is a port of both, so it accepts what they accept and throws where they
/// throw: beyond standard JSON, that is single-quoted strings, unquoted property names, comments,
/// octal and hexadecimal integers, `NaN`, `Infinity`, `undefined`, constructors and trailing
/// commas. Every value is validated, including the ones a later duplicate key replaces.
struct KurrentJSONScanner {
    /// UTF-16 units, as .NET holds the text.
    private let units: [UInt16]
    private var position = 0
    private var depth = 0

    /// Newtonsoft's default `MaxDepth`.
    static let maximumDepth = 64

    /// Decodes `data` as `new StreamReader(stream)` does: the encoding a UTF-8, UTF-16 or UTF-32
    /// byte order mark names, UTF-8 without one, and U+FFFD for every malformed sequence.
    init(_ data: Data) {
        units = Array(Self.text(of: [UInt8](data)).utf16)
    }

    /// Scans UTF-8 JSON this library produced.
    init(utf8 bytes: some Collection<UInt8>) {
        units = Array(String(decoding: bytes, as: UTF8.self).utf16)
    }

    /// The root object, which the server's `FromJsonReader` requires as the first token.
    ///
    /// Scanning stops at the closing brace: the server returns there and never reads what follows.
    mutating func scanRootObject() throws(KurrentJSONError) -> KurrentJSONValue {
        skipWhitespace()
        guard current == UInt16(ascii: "{") else {
            throw KurrentJSONError("The JSON must be an object, but starts with \(excerpt(from: position)).")
        }
        return try object()
    }

    /// One value with nothing after it.
    mutating func scanValue() throws(KurrentJSONError) -> KurrentJSONValue {
        var hasComments = false
        guard let value = try value(closer: nil, hasComments: &hasComments), !hasComments else {
            throw KurrentJSONError("The JSON holds a comment where a value is expected.")
        }
        skipWhitespace()
        guard current == nil else {
            throw unexpected("after a value")
        }
        return value
    }

    // MARK: - Encoding

    private static func text(of bytes: [UInt8]) -> String {
        // `StreamReader.DetectEncoding`, in its order.
        if bytes.starts(with: [0xFE, 0xFF]) {
            return utf16(bytes.dropFirst(2), bigEndian: true)
        }
        if bytes.starts(with: [0xFF, 0xFE]) {
            if bytes.count < 4 || bytes[2] != 0 || bytes[3] != 0 {
                return utf16(bytes.dropFirst(2), bigEndian: false)
            }
            return utf32(bytes.dropFirst(4), bigEndian: false)
        }
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(decoding: bytes.dropFirst(3), as: UTF8.self)
        }
        if bytes.starts(with: [0x00, 0x00, 0xFE, 0xFF]) {
            return utf32(bytes.dropFirst(4), bigEndian: true)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func utf16(_ bytes: ArraySlice<UInt8>, bigEndian: Bool) -> String {
        let bytes = Array(bytes)
        var units = stride(from: 0, to: bytes.count - 1, by: 2).map { index -> UInt16 in
            let (high, low) = bigEndian ? (bytes[index], bytes[index + 1]) : (bytes[index + 1], bytes[index])
            return UInt16(high) << 8 | UInt16(low)
        }
        if !bytes.count.isMultiple(of: 2) {
            units.append(0xFFFD)
        }
        return String(decoding: units, as: UTF16.self)
    }

    private static func utf32(_ bytes: ArraySlice<UInt8>, bigEndian: Bool) -> String {
        let bytes = Array(bytes)
        var scalars = stride(from: 0, to: bytes.count - 3, by: 4).map { index -> UInt32 in
            let word = bytes[index ..< index + 4]
            return (bigEndian ? Array(word) : word.reversed()).reduce(0) { $0 << 8 | UInt32($1) }
        }
        if !bytes.count.isMultiple(of: 4) {
            scalars.append(0xFFFD)
        }
        return String(decoding: scalars, as: UTF32.self)
    }

    // MARK: - Containers

    private mutating func enter() throws(KurrentJSONError) {
        depth += 1
        guard depth <= Self.maximumDepth else {
            throw KurrentJSONError("The JSON nests arrays and objects more than \(Self.maximumDepth) levels deep.")
        }
    }

    /// `ParseObject`, `ParseProperty` and `ParsePostValue`, from the opening brace.
    private mutating func object() throws(KurrentJSONError) -> KurrentJSONValue {
        let start = position
        position += 1
        try enter()
        defer { depth -= 1 }
        var members: [KurrentJSONValue.Member] = []
        var hasComments = false
        while true {
            skipWhitespace()
            guard let unit = current else {
                throw unexpectedEnd("in an object")
            }
            if unit == UInt16(ascii: "}") {
                position += 1
                break
            }
            if unit == UInt16(ascii: "/") {
                try comment()
                hasComments = true
                continue
            }
            let key = try propertyName()
            guard let value = try value(closer: nil, hasComments: &hasComments) else {
                throw unexpected("in place of a value")
            }
            members.append(.init(key: key, value: value))
            if try postValue(closer: UInt16(ascii: "}"), hasComments: &hasComments) {
                break
            }
        }
        return KurrentJSONValue(.object(members), hasComments: hasComments, source: units[start ..< position])
    }

    /// The values of an array or of a constructor's arguments, up to and including `closer`.
    private mutating func elements(closer: UInt16) throws(KurrentJSONError) -> (values: [KurrentJSONValue], hasComments: Bool) {
        try enter()
        defer { depth -= 1 }
        var values: [KurrentJSONValue] = []
        var hasComments = false
        while let value = try value(closer: closer, hasComments: &hasComments) {
            values.append(value)
            if try postValue(closer: closer, hasComments: &hasComments) {
                break
            }
        }
        return (values, hasComments)
    }

    /// `ParsePostValue`: what may follow a value. Returns whether `closer` ended the container.
    private mutating func postValue(closer: UInt16, hasComments: inout Bool) throws(KurrentJSONError) -> Bool {
        while true {
            skipWhitespace()
            switch current {
            case nil:
                throw unexpectedEnd("after a value")
            case UInt16(ascii: "}"), UInt16(ascii: "]"), UInt16(ascii: ")"):
                guard current == closer else {
                    throw unexpected("closing a container it did not open")
                }
                position += 1
                return true
            case UInt16(ascii: "/"):
                try comment()
                hasComments = true
            case UInt16(ascii: ","):
                position += 1
                return false
            default:
                throw unexpected("after a value")
            }
        }
    }

    // MARK: - Values

    /// `ParseValue`. Returns `nil` when `closer` ends the enclosing array or constructor instead.
    private mutating func value(closer: UInt16?, hasComments: inout Bool) throws(KurrentJSONError) -> KurrentJSONValue? {
        while true {
            skipWhitespace()
            guard let unit = current else {
                throw unexpectedEnd("where a value is expected")
            }
            let start = position
            let inConstructor = closer == UInt16(ascii: ")")
            switch unit {
            case UInt16(ascii: "/"):
                try comment()
                hasComments = true
                continue
            case UInt16(ascii: "]"), UInt16(ascii: ")"):
                guard unit == closer else {
                    throw unexpected("closing a container it did not open")
                }
                position += 1
                return nil
            case UInt16(ascii: ","):
                // Newtonsoft reads Undefined and leaves the comma for `ParsePostValue`.
                return KurrentJSONValue(.undefined, source: units[start ..< start])
            case UInt16(ascii: "\""), UInt16(ascii: "'"):
                position += 1
                let (text, bufferIndex) = try string(quote: unit)
                let date = NewtonsoftDate.classify(text.utf16, bufferIndex: bufferIndex)
                guard date != .conversionFails else {
                    throw KurrentJSONError("The string \(excerpt(from: start)) reads as a date outside the years 1 to 9999, which the server fails on wherever it stands.")
                }
                return KurrentJSONValue(.string(text, isDate: date == .date), source: units[start ..< position])
            case UInt16(ascii: "{"):
                return try object()
            case UInt16(ascii: "["):
                position += 1
                let (values, comments) = try elements(closer: UInt16(ascii: "]"))
                return KurrentJSONValue(.array(values), hasComments: comments, source: units[start ..< position])
            case UInt16(ascii: "t"):
                try literal("true", inConstructor: inConstructor)
                return KurrentJSONValue(.bool(true), source: units[start ..< position])
            case UInt16(ascii: "f"):
                try literal("false", inConstructor: inConstructor)
                return KurrentJSONValue(.bool(false), source: units[start ..< position])
            case UInt16(ascii: "u"):
                try literal("undefined", inConstructor: inConstructor)
                return KurrentJSONValue(.undefined, source: units[start ..< position])
            case UInt16(ascii: "n"):
                switch peek(1) {
                case UInt16(ascii: "u"):
                    try literal("null", inConstructor: inConstructor)
                    return KurrentJSONValue(.null, source: units[start ..< position])
                case UInt16(ascii: "e"):
                    return try constructor(inConstructor: inConstructor)
                default:
                    throw unexpected("where a value is expected")
                }
            case UInt16(ascii: "N"):
                try literal("NaN", inConstructor: inConstructor)
                return KurrentJSONValue(.number(.init(integer: nil, text: "NaN")), source: units[start ..< position])
            case UInt16(ascii: "I"):
                try literal("Infinity", inConstructor: inConstructor)
                return KurrentJSONValue(.number(.init(integer: nil, text: "Infinity")), source: units[start ..< position])
            case UInt16(ascii: "-") where peek(1) == UInt16(ascii: "I"):
                try literal("-Infinity", inConstructor: inConstructor)
                return KurrentJSONValue(.number(.init(integer: nil, text: "-Infinity")), source: units[start ..< position])
            case UInt16(ascii: "-"), UInt16(ascii: "."), UInt16(ascii: "0") ... UInt16(ascii: "9"):
                let number = try number()
                return KurrentJSONValue(.number(number), source: units[start ..< position])
            default:
                throw unexpected("where a value is expected")
            }
        }
    }

    /// `MatchValueWithTrailingSeparator`: the word, then the end of the text or a separator.
    private mutating func literal(_ word: String, inConstructor: Bool) throws(KurrentJSONError) {
        let expected = Array(word.utf16)
        guard position + expected.count <= units.count else {
            throw unexpectedEnd("in \(word)")
        }
        guard units[position ..< position + expected.count].elementsEqual(expected) else {
            throw unexpected("where \(word) is expected")
        }
        position += expected.count
        guard let next = current else {
            return
        }
        let isSeparator = switch next {
        case 0, UInt16(ascii: "}"), UInt16(ascii: "]"), UInt16(ascii: ","):
            true
        case UInt16(ascii: "/"):
            peek(1) == UInt16(ascii: "*") || peek(1) == UInt16(ascii: "/")
        case UInt16(ascii: ")"):
            inConstructor
        default:
            Self.isWhitespace(next)
        }
        guard isSeparator else {
            throw unexpected("after \(word)")
        }
    }

    /// `ParseConstructor`: `new Name(arguments)`.
    private mutating func constructor(inConstructor: Bool) throws(KurrentJSONError) -> KurrentJSONValue {
        let start = position
        try literal("new", inConstructor: inConstructor)
        skipWhitespace()
        let nameStart = position
        let nameEnd: Int
        while true {
            guard let unit = current else {
                throw unexpectedEnd("in a constructor")
            }
            if Self.isLetterOrDigit(unit) {
                position += 1
            } else if unit == UInt16(ascii: "(") {
                nameEnd = position
                break
            } else if unit == 0 || Self.isWhitespace(unit) {
                nameEnd = position
                position += 1
                break
            } else {
                throw unexpected("in a constructor name")
            }
        }
        guard nameEnd > nameStart else {
            throw unexpected("where a constructor name is expected")
        }
        skipWhitespace()
        guard current == UInt16(ascii: "(") else {
            throw unexpected("where a constructor's ( is expected")
        }
        position += 1
        let (arguments, comments) = try elements(closer: UInt16(ascii: ")"))
        let name = String(decoding: units[nameStart ..< nameEnd], as: UTF16.self)
        return KurrentJSONValue(.constructor(name: name, arguments: arguments), hasComments: comments, source: units[start ..< position])
    }

    // MARK: - Property names and strings

    /// `ParseProperty`: a quoted or unquoted name, then the colon.
    private mutating func propertyName() throws(KurrentJSONError) -> String {
        guard let first = current else {
            throw unexpectedEnd("in an object")
        }
        let name: String
        if first == UInt16(ascii: "\"") || first == UInt16(ascii: "'") {
            position += 1
            name = try string(quote: first).text
        } else if Self.isIdentifier(first) {
            // `ParseUnquotedProperty`: identifier characters up to whitespace, a NUL or the colon.
            let start = position
            while true {
                guard let unit = current else {
                    throw unexpectedEnd("in an unquoted property name")
                }
                if Self.isIdentifier(unit) {
                    position += 1
                } else if unit == 0 || unit == UInt16(ascii: ":") || Self.isWhitespace(unit) {
                    break
                } else {
                    throw unexpected("in an unquoted property name")
                }
            }
            name = String(decoding: units[start ..< position], as: UTF16.self)
        } else {
            throw unexpected("where a property name is expected")
        }
        skipWhitespace()
        guard current == UInt16(ascii: ":") else {
            throw current == nil ? unexpectedEnd("after a property name") : unexpected("where a property's : is expected")
        }
        position += 1
        return name
    }

    /// `ReadStringIntoBuffer`, from after the opening quote: the string with its escapes resolved.
    ///
    /// Line breaks and control characters may stand unescaped, as Newtonsoft allows. A surrogate
    /// escape without its pair becomes U+FFFD.
    ///
    /// - Returns: The string, and where Newtonsoft holds it for its date check: the index of
    ///   its first character in the reader's buffer, or 0 when an escape made the reader copy it.
    ///   The buffer starts as the text itself and shifts once the reader passes its 922nd
    ///   character, so past that point the index here is larger than the reader's.
    private mutating func string(quote: UInt16) throws(KurrentJSONError) -> (text: String, bufferIndex: Int) {
        let start = position
        var hasEscape = false
        var text: [UInt16] = []
        while true {
            guard let unit = current else {
                throw unexpectedEnd("in a string")
            }
            position += 1
            if unit == quote {
                return (String(decoding: text, as: UTF16.self), hasEscape ? 0 : start)
            }
            guard unit == UInt16(ascii: "\\") else {
                text.append(unit)
                continue
            }
            hasEscape = true
            guard let escaped = current else {
                throw unexpectedEnd("in a string")
            }
            position += 1
            switch escaped {
            case UInt16(ascii: "b"): text.append(0x08)
            case UInt16(ascii: "t"): text.append(0x09)
            case UInt16(ascii: "n"): text.append(0x0A)
            case UInt16(ascii: "f"): text.append(0x0C)
            case UInt16(ascii: "r"): text.append(0x0D)
            case UInt16(ascii: "\\"), UInt16(ascii: "\""), UInt16(ascii: "'"), UInt16(ascii: "/"):
                text.append(escaped)
            case UInt16(ascii: "u"):
                var unit = try unicodeEscape()
                if UTF16.isTrailSurrogate(unit) {
                    unit = 0xFFFD
                } else if UTF16.isLeadSurrogate(unit) {
                    var another: Bool
                    repeat {
                        another = false
                        guard position + 2 < units.count, units[position] == UInt16(ascii: "\\"), units[position + 1] == UInt16(ascii: "u") else {
                            unit = 0xFFFD
                            break
                        }
                        var lead = unit
                        position += 2
                        unit = try unicodeEscape()
                        if UTF16.isLeadSurrogate(unit) {
                            lead = 0xFFFD
                            another = true
                        } else if !UTF16.isTrailSurrogate(unit) {
                            lead = 0xFFFD
                        }
                        text.append(lead)
                    } while another
                }
                text.append(unit)
            default:
                position -= 1
                throw unexpected("after a backslash")
            }
        }
    }

    /// `ParseUnicode`: four hexadecimal digits, with at least one character after them.
    private mutating func unicodeEscape() throws(KurrentJSONError) -> UInt16 {
        guard position + 4 < units.count else {
            throw unexpectedEnd("in a \\u escape")
        }
        var value: UInt16 = 0
        for unit in units[position ..< position + 4] {
            guard let digit = Self.hexDigit(unit) else {
                throw unexpected("in a \\u escape")
            }
            value = value << 4 | UInt16(digit)
        }
        position += 4
        return value
    }

    // MARK: - Numbers

    /// `ReadNumberIntoBuffer` and `ParseReadNumber`.
    private mutating func number() throws(KurrentJSONError) -> KurrentJSONValue.Number {
        let start = position
        scan: while let unit = current {
            switch unit {
            case UInt16(ascii: "-"), UInt16(ascii: "+"), UInt16(ascii: "."), UInt16(ascii: "x"), UInt16(ascii: "X"),
                 UInt16(ascii: "0") ... UInt16(ascii: "9"), UInt16(ascii: "a") ... UInt16(ascii: "f"), UInt16(ascii: "A") ... UInt16(ascii: "F"):
                position += 1
            case 0, UInt16(ascii: ","), UInt16(ascii: "}"), UInt16(ascii: "]"), UInt16(ascii: ")"), UInt16(ascii: "/"):
                break scan
            default:
                guard Self.isWhitespace(unit) else {
                    throw unexpected("in a number")
                }
                break scan
            }
        }
        let literal = units[start ..< position].map { UInt8($0) }
        guard let number = Self.number(literal) else {
            throw KurrentJSONError("\(String(decoding: literal, as: UTF8.self)) is not a number the server reads.")
        }
        return number
    }

    /// The token `ParseReadNumber` makes of `literal`, or `nil` where it throws.
    static func number(_ literal: [UInt8]) -> KurrentJSONValue.Number? {
        let digits = UInt8(ascii: "0") ... UInt8(ascii: "9")
        guard let first = literal.first else {
            return nil
        }
        if literal.count == 1, digits ~= first {
            return .init(integer: Int64(first - UInt8(ascii: "0")), text: String(decoding: literal, as: UTF8.self))
        }
        // A leading zero not followed by a fraction or an exponent: `Convert.ToInt64` in base 16
        // after `0x`, in base 8 otherwise. Either may set the sign bit; past 64 bits it throws.
        if first == UInt8(ascii: "0"), ![UInt8(ascii: "."), UInt8(ascii: "e"), UInt8(ascii: "E")].contains(literal[1]) {
            let isHexadecimal = literal[1] == UInt8(ascii: "x") || literal[1] == UInt8(ascii: "X")
            let radix: UInt64 = isHexadecimal ? 16 : 8
            let body = isHexadecimal ? literal.dropFirst(2) : literal[...]
            guard !body.isEmpty else {
                return nil
            }
            var bits: UInt64 = 0
            for byte in body {
                guard let digit = hexDigit(UInt16(byte)), UInt64(digit) < radix else {
                    return nil
                }
                let (shifted, shiftOverflow) = bits.multipliedReportingOverflow(by: radix)
                let (next, overflow) = shifted.addingReportingOverflow(UInt64(digit))
                guard !shiftOverflow, !overflow else {
                    return nil
                }
                bits = next
            }
            let integer = Int64(bitPattern: bits)
            return .init(integer: integer, text: String(integer))
        }
        switch NewtonsoftInteger.parse(literal.map(UInt16.init), digits: 19) {
        case let .success(integer):
            return .init(integer: integer, text: String(integer))
        case .overflow:
            // A `BigInteger`, which Newtonsoft refuses past 380 characters.
            guard literal.count <= 380 else {
                return nil
            }
            let negative = first == UInt8(ascii: "-")
            let magnitude = String(decoding: literal.drop { $0 == UInt8(ascii: "-") || $0 == UInt8(ascii: "0") }, as: UTF8.self)
            return .init(integer: nil, text: magnitude.isEmpty ? "0" : (negative ? "-" : "") + magnitude)
        case .invalid:
            return float(literal).map { .init(integer: nil, text: $0) }
        }
    }

    /// `literal` in standard JSON when `double.TryParse` reads it with `NumberStyles.Float`: an
    /// optional sign, digits with an optional point, at least one digit, an optional exponent.
    private static func float(_ literal: [UInt8]) -> String? {
        let digits = UInt8(ascii: "0") ... UInt8(ascii: "9")
        var index = 0
        func take(while included: (UInt8) -> Bool) -> ArraySlice<UInt8> {
            let start = index
            while index < literal.count, included(literal[index]) {
                index += 1
            }
            return literal[start ..< index]
        }
        let sign = take { $0 == UInt8(ascii: "-") || $0 == UInt8(ascii: "+") }
        guard sign.count <= 1 else {
            return nil
        }
        let whole = take(while: digits.contains)
        var fraction: ArraySlice<UInt8>?
        if index < literal.count, literal[index] == UInt8(ascii: ".") {
            index += 1
            fraction = take(while: digits.contains)
        }
        guard !whole.isEmpty || fraction?.isEmpty == false else {
            return nil
        }
        var exponent = ""
        if index < literal.count, literal[index] == UInt8(ascii: "e") || literal[index] == UInt8(ascii: "E") {
            index += 1
            let exponentSign = take { $0 == UInt8(ascii: "-") || $0 == UInt8(ascii: "+") }
            let exponentDigits = take(while: digits.contains)
            // Without digits .NET leaves the `e` unread, and the text then fails as a whole.
            guard exponentSign.count <= 1, !exponentDigits.isEmpty else {
                return nil
            }
            exponent = "e" + String(decoding: exponentSign + exponentDigits, as: UTF8.self)
        }
        guard index == literal.count else {
            return nil
        }
        let significant = whole.drop { $0 == UInt8(ascii: "0") }
        var text = sign.first == UInt8(ascii: "-") ? "-" : ""
        text += significant.isEmpty ? "0" : String(decoding: significant, as: UTF8.self)
        if let fraction {
            text += "." + (fraction.isEmpty ? "0" : String(decoding: fraction, as: UTF8.self))
        }
        return text + exponent
    }

    // MARK: - Comments and whitespace

    /// `ParseComment`: `/* ... */`, or `// ...` up to a line break or the end of the text.
    private mutating func comment() throws(KurrentJSONError) {
        guard position + 2 < units.count else {
            throw unexpectedEnd("in a comment")
        }
        let opener = units[position + 1]
        position += 2
        if opener == UInt16(ascii: "/") {
            while let unit = current, unit != 0x0A, unit != 0x0D {
                position += 1
            }
        } else if opener == UInt16(ascii: "*") {
            while true {
                guard let unit = current else {
                    throw unexpectedEnd("in a comment")
                }
                position += 1
                if unit == UInt16(ascii: "*"), current == UInt16(ascii: "/") {
                    position += 1
                    return
                }
            }
        } else {
            position -= 1
            throw unexpected("where a comment's * or / is expected")
        }
    }

    /// `EatWhitespace`: whitespace as `char.IsWhiteSpace` decides it, and NUL characters.
    private mutating func skipWhitespace() {
        while let unit = current, unit == 0 || Self.isWhitespace(unit) {
            position += 1
        }
    }

    // MARK: - Characters

    private var current: UInt16? {
        position < units.count ? units[position] : nil
    }

    private func peek(_ offset: Int) -> UInt16? {
        position + offset < units.count ? units[position + offset] : nil
    }

    /// `char.IsWhiteSpace`: Unicode's White_Space within the Basic Multilingual Plane.
    private static func isWhitespace(_ unit: UInt16) -> Bool {
        Unicode.Scalar(unit)?.properties.isWhitespace == true
    }

    /// `char.IsLetterOrDigit`: a letter or a decimal digit within the Basic Multilingual Plane.
    private static func isLetterOrDigit(_ unit: UInt16) -> Bool {
        switch Unicode.Scalar(unit)?.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .decimalNumber:
            true
        default:
            false
        }
    }

    /// `ValidIdentifierChar`.
    private static func isIdentifier(_ unit: UInt16) -> Bool {
        unit == UInt16(ascii: "_") || unit == UInt16(ascii: "$") || isLetterOrDigit(unit)
    }

    private static func hexDigit(_ unit: UInt16) -> UInt8? {
        switch unit {
        case UInt16(ascii: "0") ... UInt16(ascii: "9"): UInt8(unit - UInt16(ascii: "0"))
        case UInt16(ascii: "a") ... UInt16(ascii: "f"): UInt8(unit - UInt16(ascii: "a") + 10)
        case UInt16(ascii: "A") ... UInt16(ascii: "F"): UInt8(unit - UInt16(ascii: "A") + 10)
        default: nil
        }
    }

    // MARK: - Errors

    private func excerpt(from start: Int) -> String {
        guard start < units.count else {
            return "the end of the text"
        }
        return String(decoding: units[start...].prefix(40), as: UTF16.self)
    }

    private func unexpected(_ place: String) -> KurrentJSONError {
        KurrentJSONError("The JSON holds \(excerpt(from: position)) \(place), at offset \(position).")
    }

    private func unexpectedEnd(_ place: String) -> KurrentJSONError {
        KurrentJSONError("The JSON ends \(place).")
    }
}
