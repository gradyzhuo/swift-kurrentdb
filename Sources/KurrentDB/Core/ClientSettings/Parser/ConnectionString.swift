//
//  ConnectionString.swift
//  KurrentCore
//

import Foundation

/// A KurrentDB connection string split into its RFC 3986 components.
///
/// The input is cut in a fixed order — scheme, authority (up to the first `/`, `?` or `#`),
/// userinfo (left of the authority's single `@`), hosts, query — and each component is parsed only
/// from its own slice. Under `.rfc3986` the raw bytes of every component are restricted to the
/// characters RFC 3986 allows there (everything else, including `@` in the query, must be
/// percent-encoded), so a character in a password or value cannot change the hosts, the
/// credentials or the parameters. Userinfo and query items are percent-decoded. Meaning and
/// validation of the parameters belong to `ClientSettings.parse(connectionString:policy:)`.
///
/// Error reasons name the component that is wrong and never echo input text: a connection string
/// may carry credentials.
package struct ConnectionString: Sendable, Equatable {
    package struct Credentials: Sendable, Equatable {
        package let username: String
        package let password: String
    }

    package let scheme: URLScheme
    package let credentials: Credentials?
    package let endpoints: [Endpoint]
    /// Query parameters. Keys are lower-cased, values percent-decoded; a key appears at most once.
    package let parameters: [String: String]

    /// - Parameter policy: Only `.rfc3986` exists today, so it needs no branching yet.
    package init(parsing string: String, policy: RFC3986Policy = .rfc3986) throws(KurrentError) {
        // The raw bytes must be an RFC 3986 scheme before lowercasing: `lowercased()` is Unicode
        // aware (the Kelvin sign would become "k"), so validation has to come first.
        guard let schemeEnd = string.range(of: "://"),
              Self.isValidSchemeBytes(string[..<schemeEnd.lowerBound]),
              let scheme = URLScheme(rawValue: string[..<schemeEnd.lowerBound].lowercased())
        else {
            throw Self.failure("Unknown or missing URL scheme; expected esdb://, kurrentdb://, kurrent:// or kdb:// (optionally with +discover).")
        }
        let rest = string[schemeEnd.upperBound...]

        guard !rest.contains("#") else {
            throw Self.failure("Connection strings take no fragment; percent-encode '#' as %23 in credentials or values.")
        }

        let authorityEnd = rest.firstIndex { $0 == "/" || $0 == "?" } ?? rest.endIndex
        let authority = rest[..<authorityEnd]
        var tail = rest[authorityEnd...]
        if tail.first == "/" {
            tail = tail.dropFirst()
        }
        let query: Substring
        if tail.isEmpty {
            query = ""
        } else if tail.first == "?" {
            query = tail.dropFirst()
        } else {
            throw Self.failure("Connection strings take no path; only '/' may follow the hosts. Percent-encode '/' as %2F in credentials.")
        }

        guard authority.utf8.filter { $0 == UInt8(ascii: "@") }.count <= 1 else {
            throw Self.failure("The authority holds more than one '@'; percent-encode '@' as %40 in credentials.")
        }
        let hostList: Substring
        if let at = authority.firstIndex(of: "@") {
            credentials = try Self.parseCredentials(authority[..<at])
            hostList = authority[authority.index(after: at)...]
        } else {
            credentials = nil
            hostList = authority
        }

        self.scheme = scheme
        endpoints = try Self.parseEndpoints(hostList)
        parameters = try Self.parseParameters(query)
    }

    // MARK: - Components

    private static func parseCredentials(_ userinfo: Substring) throws(KurrentError) -> Credentials {
        guard let colon = userinfo.firstIndex(of: ":") else {
            throw failure("Credentials must be 'username:password'; percent-encode ':' in the username as %3A.")
        }
        try validateBytes(userinfo, allowed: userinfoSpecials, component: "credentials")
        let username = try percentDecoded(userinfo[..<colon], field: "username")
        let password = try percentDecoded(userinfo[userinfo.index(after: colon)...], field: "password")
        guard !username.isEmpty else {
            throw failure("The username in the credentials is empty.")
        }
        return Credentials(username: username, password: password)
    }

    private static func parseEndpoints(_ hostList: Substring) throws(KurrentError) -> [Endpoint] {
        guard !hostList.isEmpty else {
            throw failure("Connection string doesn't have a host.")
        }
        var endpoints: [Endpoint] = []
        for entry in hostList.split(separator: ",", omittingEmptySubsequences: false) {
            guard !entry.hasPrefix("[") else {
                throw failure("IPv6 address literals are not supported.")
            }
            let host: Substring
            var port: UInt32?
            if let colon = entry.firstIndex(of: ":") {
                host = entry[..<colon]
                let portText = entry[entry.index(after: colon)...]
                guard !portText.isEmpty,
                      portText.utf8.allSatisfy(isDigit),
                      let value = UInt32(portText),
                      (1 ... 65535).contains(value)
                else {
                    throw failure("Every host port must be a number from 1 to 65535.")
                }
                port = value
            } else {
                host = entry
            }
            guard isValidHost(host) else {
                throw failure("Every host must be a host name or an IPv4 address.")
            }
            endpoints.append(Endpoint(host: String(host), port: port))
        }
        return endpoints
    }

    private static func parseParameters(_ query: Substring) throws(KurrentError) -> [String: String] {
        var parameters: [String: String] = [:]
        // Everything here works on UTF-8 bytes: a Character-based split would let a combining mark
        // after '&' or '=' glue itself to the delimiter, hide the separator and leak the value.
        for itemBytes in query.utf8.split(separator: UInt8(ascii: "&"), omittingEmptySubsequences: true) {
            let item = Substring(itemBytes)
            let equals = itemBytes.firstIndex(of: UInt8(ascii: "="))
            // The name is everything before the first '=' byte; it never holds any of the value.
            let name = displayName(String(decoding: itemBytes[..<(equals ?? itemBytes.endIndex)], as: UTF8.self))
            guard let equals else {
                throw failure("Parameter '\(name)' has no value; expected 'name=value'.")
            }
            try validateBytes(item, allowed: queryKeySpecials + "=", component: "parameter '\(name)'")
            // The item is pure ASCII now, so splitting at the '=' is safe.
            let rawKey = Substring(itemBytes[..<equals])
            let rawValue = Substring(itemBytes[itemBytes.index(after: equals)...])
            let key = try percentDecoded(rawKey, field: "parameter '\(name)'").lowercased()
            guard !key.isEmpty else {
                throw failure("A connection string parameter has an empty name.")
            }
            let value = try percentDecoded(rawValue, field: "value of '\(displayName(key))'")
            guard parameters.updateValue(value, forKey: key) == nil else {
                throw failure("Duplicate connection string parameter '\(displayName(key))'.")
            }
        }
        return parameters
    }

    // MARK: - Helpers

    /// Host names (ASCII letters, digits, '-', '_', '.') or dotted-quad IPv4. A name whose labels
    /// are all numeric must be a valid IPv4 address, so "192.168" is rejected.
    private static func isValidHost(_ written: Substring) -> Bool {
        // One trailing '.' marks a fully qualified name; it is kept as written but not validated.
        let host = written.hasSuffix(".") ? written.dropLast() : written
        guard !host.isEmpty else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.allSatisfy({ !$0.isEmpty }) else { return false }
        let allowedBytes = host.utf8.allSatisfy { byte in
            isDigit(byte)
                || (UInt8(ascii: "a") ... UInt8(ascii: "z")).contains(byte)
                || (UInt8(ascii: "A") ... UInt8(ascii: "Z")).contains(byte)
                || byte == UInt8(ascii: "-") || byte == UInt8(ascii: "_") || byte == UInt8(ascii: ".")
        }
        guard allowedBytes else { return false }
        // Resolvers (inet_aton, getaddrinfo) read leading-zero labels as octal and "0x" labels as
        // hex, so a host made only of such labels must be a strict dotted-quad: four decimal
        // labels, 0...255, no leading zero.
        if labels.allSatisfy(isNumericLike) {
            return labels.count == 4 && labels.allSatisfy { label in
                label.utf8.allSatisfy(isDigit)
                    && (label.count == 1 || label.first != "0")
                    && UInt8(label) != nil
            }
        }
        return true
    }

    /// All decimal digits, or `0x`/`0X` followed by zero or more hex digits.
    private static func isNumericLike(_ label: Substring) -> Bool {
        if label.utf8.allSatisfy(isDigit) { return true }
        let bytes = Array(label.utf8)
        return bytes.count >= 2 && bytes[0] == UInt8(ascii: "0")
            && (bytes[1] == UInt8(ascii: "x") || bytes[1] == UInt8(ascii: "X"))
            && bytes[2...].allSatisfy { hexValue($0) != nil }
    }

    /// RFC 3986 `scheme = ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )`, ASCII only.
    private static func isValidSchemeBytes(_ scheme: Substring) -> Bool {
        guard let first = scheme.utf8.first, isAlpha(first) else { return false }
        return scheme.utf8.allSatisfy { isAlpha($0) || isDigit($0) || $0 == UInt8(ascii: "+") || $0 == UInt8(ascii: "-") || $0 == UInt8(ascii: ".") }
    }

    private static func isAlpha(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "a") ... UInt8(ascii: "z")).contains(byte) || (UInt8(ascii: "A") ... UInt8(ascii: "Z")).contains(byte)
    }

    private static let userinfoSpecials = "-._~!$&'()*+,;=:%"
    private static let queryKeySpecials = "-._~!$'()*+,;:/?%"

    /// Rejects any raw byte outside the RFC 3986 set for a component. Works on the UTF-8 view, so a
    /// non-ASCII scalar (including a combining mark after a delimiter) is always rejected.
    /// The reason never echoes the offending text.
    private static func validateBytes(_ text: Substring, allowed specials: String, component: String) throws(KurrentError) {
        let special = Set(specials.utf8)
        for byte in text.utf8 {
            let alphanumeric = isDigit(byte)
                || (UInt8(ascii: "a") ... UInt8(ascii: "z")).contains(byte)
                || (UInt8(ascii: "A") ... UInt8(ascii: "Z")).contains(byte)
            if alphanumeric || special.contains(byte) { continue }
            if byte == UInt8(ascii: "@") {
                throw failure("An unencoded '@' is not allowed in the \(component); write it as %40. For an arbitrary password use ClientSettings.authenticated(.credentials(username:password:)).")
            }
            throw failure("The \(component) contains a character that must be percent-encoded (whitespace, non-ASCII, control characters and \" < > \\ ^ ` { | } are not allowed raw).")
        }
    }

    /// A key name made safe to put in an error reason: non-printable and non-ASCII scalars are
    /// escaped as `\u{XX}` and the result is capped at 64 characters with a trailing `…`.
    package static func displayName(_ key: String) -> String {
        let limit = 64
        var result = ""
        for scalar in key.unicodeScalars {
            let piece = (0x20 ... 0x7E).contains(scalar.value)
                ? String(Character(scalar))
                : "\\u{" + (scalar.value < 0x10 ? "0" : "") + String(scalar.value, radix: 16, uppercase: true) + "}"
            if result.count + piece.count > limit {
                return result + "…"
            }
            result += piece
        }
        return result
    }

    private static func percentDecoded(_ text: Substring, field: String) throws(KurrentError) -> String {
        guard text.contains("%") else { return String(text) }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(text.utf8.count)
        var iterator = text.utf8.makeIterator()
        while let byte = iterator.next() {
            guard byte == UInt8(ascii: "%") else {
                bytes.append(byte)
                continue
            }
            guard let high = iterator.next().flatMap(hexValue), let low = iterator.next().flatMap(hexValue) else {
                throw failure("Invalid percent-encoding in the \(field).")
            }
            bytes.append(high << 4 | low)
        }
        guard let decoded = String(validating: bytes, as: UTF8.self) else {
            throw failure("The \(field) is not valid UTF-8 after percent-decoding.")
        }
        return decoded
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(byte)
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0") ... UInt8(ascii: "9"): byte - UInt8(ascii: "0")
        case UInt8(ascii: "A") ... UInt8(ascii: "F"): byte - UInt8(ascii: "A") + 10
        case UInt8(ascii: "a") ... UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
        default: nil
        }
    }

    private static func failure(_ reason: String) -> KurrentError {
        .internalParsingError(reason: reason)
    }
}
