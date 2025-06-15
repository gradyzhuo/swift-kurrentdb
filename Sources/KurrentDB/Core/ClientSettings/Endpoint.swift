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

    package init(host: String, port: UInt32? = nil) {
        self.host = host
        self.port = port ?? DEFAULT_PORT_NUMBER
    }

    public var isLocalhost: Bool {
        ["127.0.0.1", "localhost"].contains(host)
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
