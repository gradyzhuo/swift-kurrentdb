//
//  ConnectionString.swift
//  KurrentCore
//

/// A KurrentDB connection string split into its RFC 3986 components.
///
/// The input is cut in a fixed order — scheme, authority (up to the first `/`, `?` or `#`),
/// userinfo (left of the authority's last `@`), hosts, query — and each component is parsed only
/// from its own slice, so characters in a password can never change hosts or parameters.
/// Userinfo and query items are percent-decoded. Meaning and validation of the parameters belong
/// to `ClientSettings.parse(connectionString:)`.
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

    package init(parsing string: String) throws(KurrentError) {
        guard let schemeEnd = string.range(of: "://"),
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

        let hostList: Substring
        if let at = authority.lastIndex(of: "@") {
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
        for item in query.split(separator: "&", omittingEmptySubsequences: true) {
            guard let equals = item.firstIndex(of: "=") else {
                throw failure("Every connection string parameter must be 'name=value'.")
            }
            let key = try percentDecoded(item[..<equals], field: "parameter name").lowercased()
            guard !key.isEmpty else {
                throw failure("A connection string parameter has an empty name.")
            }
            let value = try percentDecoded(item[item.index(after: equals)...], field: "value of '\(key)'")
            guard parameters.updateValue(value, forKey: key) == nil else {
                throw failure("Duplicate connection string parameter '\(key)'.")
            }
        }
        return parameters
    }

    // MARK: - Helpers

    /// Host names (ASCII letters, digits, '-', '_', '.') or dotted-quad IPv4. A name whose labels
    /// are all numeric must be a valid IPv4 address, so "192.168" is rejected.
    private static func isValidHost(_ host: Substring) -> Bool {
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
        if labels.allSatisfy({ $0.utf8.allSatisfy(isDigit) }) {
            return labels.count == 4 && labels.allSatisfy { UInt8($0) != nil }
        }
        return true
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
