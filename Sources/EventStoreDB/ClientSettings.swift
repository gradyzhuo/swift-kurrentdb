//
//  ClientSettings.swift
//
//
//  Created by Grady Zhuo on 2023/10/17.
//

import Foundation
import GRPC
import Logging
import NIOCore
import NIOPosix
import NIOSSL
import RegexBuilder

let logger = Logger(label: "ClientSettings")

public let DEFAULT_PORT_NUMBER: UInt32 = 2113
public let DEFAULT_GOSSIP_TIMEOUT: TimeInterval = 3.0

public struct ClientSettings {
    public var configuration: TLSConfiguration
    public private(set) var clusterMode: TopologyClusterMode
    public private(set) var numberOfThreads: Int = 1

    public private(set) var tls: Bool = false
    public private(set) var tlsVerifyCert: Bool = false

    public private(set) var defaultDeadline: Int = .max
    public private(set) var connectionName: String?

    public var keepAlive: KeepAlive = .default
    public var defaultUserCredentials: UserCredentials?

    public init(clusterMode: TopologyClusterMode, configuration: TLSConfiguration, numberOfThreads: Int) {
        self.clusterMode = clusterMode
        self.configuration = configuration
        self.numberOfThreads = numberOfThreads
    }

    public init(clusterMode: TopologyClusterMode, numberOfThreads: Int = 1, configure: () -> TLSConfiguration = { .clientDefault }) {
        self.init(clusterMode: clusterMode, configuration: configure(), numberOfThreads: numberOfThreads)
    }

    public func makeCallOptions() throws -> CallOptions {
        var options = CallOptions()
        if let user = defaultUserCredentials {
            try options.customMetadata.replaceOrAdd(name: "Authorization", value: user.basicAuthHeader)
        }
        return options
    }
}

extension GRPCChannelPool {
    public static func with(settings: ClientSettings) throws -> GRPCChannel {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: settings.numberOfThreads)

        let transportSecurity = if settings.tls {
            GRPCChannelPool.Configuration.TransportSecurity.tls(.makeClientConfigurationBackedByNIOSSL(configuration: settings.configuration))
        } else {
            GRPCChannelPool.Configuration.TransportSecurity.plaintext
        }

        return switch settings.clusterMode {
        case let .singleNode(endpoint):
            try Self.with(
                target: endpoint.connectionTarget(),
                transportSecurity: transportSecurity,
                eventLoopGroup: group
            )
        case let .dnsDiscovery(endpoint, _, _):
            try Self.with(
                target: endpoint.connectionTarget(),
                transportSecurity: transportSecurity,
                eventLoopGroup: group
            )
        case let .gossipCluster(endpoints, _, _):
            try Self.with(
                target: endpoints.first!.connectionTarget(),
                transportSecurity: transportSecurity,
                eventLoopGroup: group
            )
        }
    }
}

//
extension ClientSettings {
    enum ValidScheme: String {
        case esdb
        case dnsDiscover = "esdb+discover"
    }

    public static func localhost(port: UInt32 = DEFAULT_PORT_NUMBER, numberOfThreads: Int = 1, userCredentials: UserCredentials? = nil, trustRoots: NIOSSLTrustRoots? = nil) -> Self {
        var settings: Self = .init(clusterMode: .singleNode(at: .init(host: "localhost", port: port)), numberOfThreads: numberOfThreads)
        
        if let trustRoots{
            settings.configuration.trustRoots = trustRoots
            settings.tls = true
        }else{
            settings.tls = false
        }
        
        settings.defaultUserCredentials = userCredentials
        return settings
    }

    private static func parseScheme(_ connectionString: String) -> ValidScheme? {
        let _scheme = Reference(String.self)
        let schemeRegex = Regex {
            Capture(as: _scheme) {
                OneOrMore(.any)
            }
            transform: {
                String($0)
            }
            "://"
        }

        let schemeMatch = connectionString.firstMatch(of: schemeRegex)
        return schemeMatch.flatMap {
            .init(rawValue: $0[_scheme])
        }
    }

    private static func parseUserAndPassowrd(_ connectionString: String) -> UserCredentials? {
        let _user = Reference(String.self)
        let _password = Reference(String.self)
        let userAndPasswordRegex = Regex {
            Capture(as: _user) {
                OneOrMore(.any.subtracting(.anyOf(":@/")))
            } transform: {
                String($0)
            }
            ":"
            Optionally {
                Capture(as: _password) {
                    OneOrMore(.any.subtracting(.anyOf(":@")))
                } transform: {
                    String($0)
                }
            }
            "@"
        }

        guard let userAndPasswordMatch = connectionString.firstMatch(of: userAndPasswordRegex) else {
            return nil
        }

        return .init(username: userAndPasswordMatch[_user], password: userAndPasswordMatch[_password])
    }

    private static func parseEndpoints(_ connectionString: String) -> [Endpoint] {
        var connectionString = connectionString
        if let atIndex = connectionString.firstIndex(of: "@") {
            let range = connectionString.startIndex ..< atIndex
            connectionString.replaceSubrange(range, with: "")
        }

        let _host = Reference(Substring.self)
        let _port = Reference(UInt32?.self)

        let hostsRegex = Regex {
            ChoiceOf {
                "://"
                "@"
                ","
            }
            Capture(as: _host) {
                OneOrMore(
                    .any
                        .subtracting(
                            .anyOf(":?=&")
                        )
                )
            }

            Optionally {
                ":"
                TryCapture(OneOrMore(.digit), as: _port) {
                    UInt32($0, radix: 10)
                }
            }
        }

        let hostMatches = connectionString.matches(of: hostsRegex)

        return hostMatches.map {
            .init(host: $0[_host].description, port: $0[_port])
        }
    }

    private static func parseQueryItems(_ connectionString: String) -> [URLQueryItem] {
        let _key = Reference(String.self)
        let _value = Reference(String.self)
        let queryItemsRegex = Regex {
            ChoiceOf {
                "?"
                "&"
            }
            Capture(as: _key) {
                OneOrMore {
                    .any.subtracting(.anyOf("?&="))
                }
            } transform: {
                String($0)
            }

            "="
            Capture(as: _value) {
                OneOrMore {
                    .any.subtracting(.anyOf("?&="))
                }
            } transform: {
                String($0)
            }
        }

        let queryItemsMatches = connectionString.matches(of: queryItemsRegex)

        return queryItemsMatches.map {
            .init(name: $0[_key], value: $0[_value])
        }
    }

    public static func parse(connectionString: String) throws -> Self {
        guard let scheme = parseScheme(connectionString) else {
            throw ClientSettingsError.parseError(message: "Unknown URL scheme: \(connectionString)")
        }

        let endpoints = parseEndpoints(connectionString)

        guard endpoints.count > 0 else {
            throw ClientSettingsError.parseError(message: "Connection string doesn't have an host")
        }

        let parsedResult = parseQueryItems(connectionString)

        let queryItems: [String: URLQueryItem] = .init(uniqueKeysWithValues: parsedResult.map {
            ($0.name.lowercased(), $0)
        })

        let clusterMode: TopologyClusterMode
        if endpoints.count > 1 {
            // gossip mode
            let nodePreference = queryItems["nodepreference"]?.value.flatMap {
                TopologyClusterMode.NodePreference(rawValue: $0)
            } ?? .leader
            let gossipTimeout: TimeInterval = queryItems["gossiptimeout"].flatMap { $0.value.flatMap { TimeInterval($0) } } ?? DEFAULT_GOSSIP_TIMEOUT
            clusterMode = .gossipCluster(endpoints: endpoints, nodePreference: nodePreference, timeout: gossipTimeout)
        } else {
            let endpoint = endpoints.first!
            if scheme == .dnsDiscover {
                // dns discovery mode
                let maxDiscoverAttempts = queryItems["maxdiscoverattempts"].flatMap { $0.value.flatMap { Int($0) } } ?? 3
                let discoverInterval = queryItems["discoveryinterval"].flatMap { $0.value.flatMap { TimeInterval($0) } } ?? 0.5
                clusterMode = .dnsDiscovery(from: endpoint, interval: discoverInterval, maxAttempts: maxDiscoverAttempts)
            } else {
                // singleMode
                clusterMode = .singleNode(at: endpoint)
            }
        }

        var settings = Self(clusterMode: clusterMode)
        settings.defaultUserCredentials = parseUserAndPassowrd(connectionString)

        if let keepAliveInterval: TimeInterval = (queryItems["keepaliveinterval"].flatMap { $0.value.flatMap { .init($0) } }),
           let keepAliveTimeout: TimeInterval = (queryItems["keepalivetimeout"].flatMap { $0.value.flatMap { .init($0) } }) {
            settings.keepAlive = .init(interval: keepAliveInterval, timeout: keepAliveTimeout)
        }

        if let connectionName = queryItems["connectionanme"]?.value {
            settings.connectionName = connectionName
        }

        if let tlsItem = queryItems["tls"], tlsItem.value == "false" {
            settings.tls = false
        } else {
            settings.tls = true
        }
        if let tls: Bool = (queryItems["tls"].flatMap { $0.value.flatMap { .init($0) } }) {
            settings.tls = tls
        }

        if let tlsVerifyCert: Bool = (queryItems["tlsverifycert"].flatMap { $0.value.flatMap { .init($0) } }) {
            settings.tlsVerifyCert = tlsVerifyCert
        }

        if let defaultDeadline: Int = (queryItems["defaultdeadline"].flatMap { $0.value.flatMap { .init($0) }}) {
            settings.defaultDeadline = defaultDeadline
        }

        return settings
    }
}

extension ClientSettings {
    public enum TopologyClusterMode {
        public enum NodePreference: String {
            case leader
            case follower
            case random
            case readOnlyReplica = "readonlyreplica"
        }

        case singleNode(at: Endpoint)
        case dnsDiscovery(from: Endpoint, interval: TimeInterval, maxAttempts: Int)
        case gossipCluster(endpoints: [Endpoint], nodePreference: NodePreference, timeout: TimeInterval)

        static func gossipCluster(endpoints: [Endpoint], nodePreference: NodePreference) -> Self {
            .gossipCluster(endpoints: endpoints, nodePreference: nodePreference, timeout: DEFAULT_GOSSIP_TIMEOUT)
        }
    }

    public struct Endpoint {
        let host: String
        let port: UInt32

        init(host: String, port: UInt32? = nil) {
            self.host = host
            self.port = port ?? DEFAULT_PORT_NUMBER
        }

        public func connectionTarget() -> ConnectionTarget {
            .host(host, port: Int(port))
        }
    }
}

extension ClientSettings: ExpressibleByStringLiteral {
    public typealias StringLiteralType = String

    public init(stringLiteral value: String) {
        do {
            self = try Self.parse(connectionString: value)
        } catch let ClientSettingsError.parseError(message) {
            logger.error(.init(stringLiteral: message))
            fatalError(message)

        } catch {
            logger.error(.init(stringLiteral: "\(error)"))
            fatalError(error.localizedDescription)
        }
    }
}
