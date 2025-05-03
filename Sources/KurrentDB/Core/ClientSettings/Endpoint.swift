//
//  ClientSettings.Endpoint.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2025/2/7.
//

import GRPCNIOTransportCore
import Network

public struct Endpoint: Sendable {
    let host: String
    let port: UInt32

    package init(host: String, port: UInt32? = nil) {
        self.host = host
        self.port = port ?? DEFAULT_PORT_NUMBER
    }
}

extension Endpoint: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.host == rhs.host && lhs.port == rhs.port
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
            return if let _ = IPv4Address(host) {
                .ipv4(host: host, port: Int(port))
            } else if let _ = IPv6Address(host) {
                .ipv6(host: host, port: Int(port))
            } else {
                .dns(host: host, port: Int(port))
            }
        }
    }
}
