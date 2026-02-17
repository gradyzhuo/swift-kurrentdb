//
//  Endpoint.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2025/2/7.
//

import GRPCNIOTransportCore
import NIO

public struct Endpoint: Sendable {
    let host: String
    let port: UInt32

    public init(host: String, port: UInt32? = nil) {
        self.host = host
        self.port = port ?? DEFAULT_PORT_NUMBER
    }

    public var isLocalhost: Bool {
        ["127.0.0.1", "localhost"].contains(host)
    }
}

extension Endpoint {
    /// Initializes an `Endpoint` from a string in the format `"host:port"` or `"host"`.
    ///
    /// - `"db.example.com:2113"` → host: `db.example.com`, port: `2113`
    /// - `"db.example.com"` → host: `db.example.com`, port: `2113` (default)
    /// - `"127.0.0.1:2114"` → host: `127.0.0.1`, port: `2114`
    ///
    /// Returns `nil` if the string is empty.
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
    public init(stringLiteral value: String) {
        self = Endpoint(string: value)!
    }
}

extension Endpoint: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.host == rhs.host && lhs.port == rhs.port
    }
}

extension Endpoint: CustomStringConvertible {
    public var description: String {
        "\(Self.self)(\(host):\(port))"
    }
}

extension Endpoint: CustomDebugStringConvertible {
    public var debugDescription: String {
        "\(host):\(port)"
    }
}

extension Endpoint {
    public var target: ResolvableTarget {
        get throws {
            let port = Int(port)
            guard let resolvedAddress = try? SocketAddress(ipAddress: host, port: Int(port)) else {
                return .dns(host: host, port: port)
            }

            return switch resolvedAddress {
            case .v4:
                .ipv4(host: host, port: port)
            case .v6:
                .ipv6(host: host, port: port)
            default:
                .dns(host: host, port: port)
            }
        }
    }
}
