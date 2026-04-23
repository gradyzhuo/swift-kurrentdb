//
//  Endpoint.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2025/2/7.
//

import GRPCNIOTransportCore
import NIO

/// Network address of a single KurrentDB node, expressed as a host and port pair.
///
/// Endpoints can be created from string literals for convenience:
///
/// ```swift
/// let endpoint: Endpoint = "db.example.com:2113"
/// let defaultPort: Endpoint = "db.example.com"  // port defaults to 2113
/// ```
public struct Endpoint: Sendable {
    /// DNS name or IP address of the server.
    let host: String
    /// TCP port the server is listening on.
    let port: UInt32

    /// Creates an endpoint with an explicit host and optional port.
    ///
    /// - Parameters:
    ///   - host: DNS name or IP address of the server.
    ///   - port: TCP port number. Defaults to `DEFAULT_PORT_NUMBER` (2113) when `nil`.
    public init(host: String, port: UInt32? = nil) {
        self.host = host
        self.port = port ?? DEFAULT_PORT_NUMBER
    }

    /// Returns `true` when the host resolves to the local machine.
    public var isLocalhost: Bool {
        ["127.0.0.1", "localhost"].contains(host)
    }
}

extension Endpoint {
    /// Creates an `Endpoint` by parsing a `"host"` or `"host:port"` string.
    ///
    /// - Parameter string: A non-empty string in `"host"` or `"host:port"` format.
    /// - Returns: A configured `Endpoint`, or `nil` if `string` is empty.
    public init?(string: String) {
        let parts = string.split(separator: ":", maxSplits: 1)
        guard let host = parts.first.map(String.init) else {
            return nil
        }
        let port: UInt32 = if parts.count > 1, let parsed = UInt32(parts[1]) {
            parsed
        } else {
            DEFAULT_PORT_NUMBER
        }
        self.init(host: host, port: port)
    }
}

extension Endpoint: ExpressibleByStringLiteral {
    /// Creates an `Endpoint` from a `"host"` or `"host:port"` string literal.
    ///
    /// - Parameter value: A string in `"host"` or `"host:port"` format.
    ///
    /// > Important: Calls `preconditionFailure` if `value` is empty or malformed.
    public init(stringLiteral value: String) {
        guard let endpoint = Endpoint(string: value) else {
            preconditionFailure("Invalid endpoint string literal: \"\(value)\". Expected format: \"host\" or \"host:port\".")
        }
        self = endpoint
    }
}

extension Endpoint: Equatable {
    /// Returns true if both endpoints have the same host and port.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.host == rhs.host && lhs.port == rhs.port
    }
}

extension Endpoint: CustomStringConvertible {
    /// Human-readable representation in the form `Endpoint(host:port)`.
    public var description: String {
        "\(Self.self)(\(host):\(port))"
    }
}

extension Endpoint: CustomDebugStringConvertible {
    /// Compact `host:port` string, suitable for logging and debugging.
    public var debugDescription: String {
        "\(host):\(port)"
    }
}

extension Endpoint {
    /// Resolves the endpoint to an NIO `ResolvableTarget`, choosing IPv4, IPv6, or DNS as appropriate.
    ///
    /// The current implementation always succeeds; the `throws` signature is retained for future compatibility.
    public var target: ResolvableTarget {
        get throws {
            let port = Int(port)
            guard let resolvedAddress = try? SocketAddress(ipAddress: host, port: Int(port)) else {
                return .dns(host: host, port: port)
            }

            return switch resolvedAddress {
            case .v4:
                .ipv4(address: host, port: port)
            case .v6:
                .ipv6(address: host, port: port)
            default:
                .dns(host: host, port: port)
            }
        }
    }
}
