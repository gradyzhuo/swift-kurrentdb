//
//  ClientSettings.swift
//  KurrentCore
//
//  Created by Grady Zhuo on 2023/10/17.
//

import Foundation
import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2
import Logging
import NIOCore
import NIOPosix
import NIOSSL
import NIOTransportServices
import RegexBuilder

public let DEFAULT_PORT_NUMBER: UInt32 = 2113

/// `ClientSettings` encapsulates various configuration settings for a client.
///
/// - Properties:
///   - `configuration`: TLS configuration.
///   - `clusterMode`: The cluster topology mode.
///   - `secure`: Indicates if TLS is enabled (default is false).
///   - `tlsVerifyCert`: Indicates if TLS certificate verification is enabled (default is false).
///   - `defaultDeadline`: Default deadline for operations (default is `.max`).
///   - `connectionName`: Optional connection name.
///   - `keepAlive`: Keep-alive settings.
///   - `defaultUserCredentials`: Optional user credentials.
///
/// - Initializers:
///   - `init(clusterMode:configuration:numberOfThreads)`: Initializes with specified cluster mode, TLS configuration, and number of threads.
///   - `init(clusterMode:numberOfThreads:configure)`: Initializes with specified cluster mode, number of threads, and TLS configuration using a configuration closure.
///
/// - Methods:
///   - `makeCallOptions()`: Creates call options for making requests, optionally including user credentials.
///
/// - Static Methods:
///   - `localhost(port:numberOfThreads:userCredentials:trustRoots)`: Returns settings configured for localhost with optional port, number of threads, user credentials, and trust roots.
///   - `parse(connectionString)`: Parses a connection string into `ClientSettings`.
///
/// - Nested Types:
///   - `TopologyClusterMode`: Defines the cluster topology modes.
///   - `Endpoint`: Represents a network endpoint with a host and port.
///
/// - Conformance:
///   - `ExpressibleByStringLiteral`: Allows initialization from a string literal.
///
/// - Example:
///   - single node mode, initiating gRPC communication on the specified port on localhost and using 2 threads.
///
///   ```swift
///   let clientSettingsSingleNode = ClientSettings(
///       clusterMode: .singleNode(at: .init(host: "localhost", port: 50051)),
///       configuration: .clientDefault,
///       numberOfThreads: 2
///   )
///   ```
///   - Gossip cluster mode, specifying multiple nodes' hosts and ports, as well as node preference and timeout, using 3 threads.
///   ```swift
///   let clientSettingsGossipCluster = ClientSettings(
///       clusterMode: .gossipCluster(
///           endpoints: [.init(host: "node1.example.com", port: 50051), .init(host: "node2.example.com", port: 50052)],
///           nodePreference: .leader,
///           timeout: 5.0
///       ),
///       configuration: .clientDefault,
///       numberOfThreads: 3
///   )
///   ```

public struct ClientSettings: Sendable {
    public private(set) var endpoints: [Endpoint]
    public var cerificates: [TLSConfig.CertificateSource]

    public private(set) var dnsDiscover: Bool
    public private(set) var nodePreference: NodePreference
    public private(set) var gossipTimeout: Duration

    public private(set) var secure: Bool
    public private(set) var tlsVerifyCert: Bool

    public private(set) var defaultDeadline: Int
    public private(set) var connectionName: String?

    public var keepAlive: KeepAlive
    public var authentication: Authentication?
    public var discoveryInterval: Duration
    public var maxDiscoveryAttempts: UInt16

    public init(
        clusterMode: TopologyClusterMode? = nil,
        cerificates: [TLSConfig.CertificateSource] = [],
        nodePreference: NodePreference = .leader,
        gossipTimeout: Duration = .seconds(3),
        secure: Bool = false,
        tlsVerifyCert: Bool = false,
        defaultDeadline: Int = .max,
        connectionName: String? = nil,
        keepAlive: KeepAlive = .default,
        authentication: Authentication? = nil,
        discoveryInterval: Duration = .microseconds(100),
        maxDiscoveryAttempts: UInt16 = 10
    ) {
        self.cerificates = cerificates
        self.nodePreference = nodePreference
        self.gossipTimeout = gossipTimeout
        self.secure = secure
        self.tlsVerifyCert = tlsVerifyCert
        self.defaultDeadline = defaultDeadline
        self.connectionName = connectionName
        self.keepAlive = keepAlive
        self.authentication = authentication
        self.discoveryInterval = discoveryInterval
        self.maxDiscoveryAttempts = maxDiscoveryAttempts

        if let clusterMode {
            switch clusterMode {
            case let .dns(domain):
                self.endpoints = [domain]
                self.dnsDiscover = true
            case let .seeds(endpoints):
                self.endpoints = endpoints
                self.dnsDiscover = false
            case let .standalone(endpoint):
                self.endpoints = [endpoint]
                self.dnsDiscover = false
            }
        } else {
            self.endpoints = []
            self.dnsDiscover = false
        }
    }
    
}

extension ClientSettings {
    public var clusterMode: TopologyClusterMode {
        if dnsDiscover {
            .dns(domain: endpoints[0])
        } else if endpoints.count > 1 {
            .seeds(endpoints)
        } else {
            .standalone(endpoint: endpoints[0])
        }
    }

    public var trustRoots: TLSConfig.TrustRootsSource? {
        guard secure else {
            return nil
        }
        return if cerificates.isEmpty {
            .systemDefault
        } else {
            .certificates(cerificates)
        }
    }

    public func httpUri(endpoint: Endpoint) -> URL? {
        var components = URLComponents()
        components.scheme = secure ? "https" : "http"
        components.host = endpoint.host
        components.port = Int(endpoint.port)
        return components.url
    }
}

extension ClientSettings {
    public static func localhost() -> Self {
        localhost(ports: DEFAULT_PORT_NUMBER)
    }

    public static func localhost(ports: UInt32...) -> Self {
        let endpoints = ports.map { Endpoint(host: "localhost", port: $0) }
        let clusterMode: TopologyClusterMode = if endpoints.count == 1 {
            .standalone(endpoint: endpoints[0])
        } else {
            .seeds(endpoints)
        }
        return Self(clusterMode: clusterMode)
    }

    public static func parse(connectionString: String) throws(KurrentError) -> Self {
        let schemeParser = URLSchemeParser()
        let endpointParser = EndpointParser()
        let queryItemParser = QueryItemParser()
        let userCredentialParser = UserCredentialsParser()

        guard let scheme = schemeParser.parse(connectionString) else {
            throw KurrentError.internalParsingError(reason: "Unknown URL scheme: \(connectionString)")
        }

        guard let endpoints = endpointParser.parse(connectionString),
              endpoints.count > 0
        else {
            throw KurrentError.internalParsingError(reason: "Connection string doesn't have an host")
        }

        let parsedResult = queryItemParser.parse(connectionString) ?? []

        let queryItems: [String: URLQueryItem] = .init(uniqueKeysWithValues: parsedResult.map {
            ($0.name.lowercased(), $0)
        })

        let clusterMode: TopologyClusterMode = if scheme == .dnsDiscover {
            .dns(domain: endpoints[0])
        } else if endpoints.count > 1 {
            .seeds(endpoints)
        } else {
            .standalone(endpoint: endpoints[0])
        }

        let nodePreference = queryItems["nodepreference"]?.value.flatMap {
            NodePreference(rawValue: $0)
        } ?? .leader

        let gossipTimeout: Duration = queryItems["gossiptimeout"]
            .flatMap({ $0.value.flatMap { Int64($0) } })
            .map { .microseconds($0) } ?? .seconds(3)

        let maxDiscoveryAttempts: UInt16 = queryItems["maxdiscoverattempts"]
            .flatMap({ $0.value.flatMap { UInt16($0) } }) ?? 10

        let discoveryInterval: Duration = queryItems["discoveryinterval"]
            .flatMap({ $0.value.flatMap { Int64($0) } })
            .map { .microseconds($0) } ?? .microseconds(100)

        let authentication = userCredentialParser.parse(connectionString)

        let keepAlive: KeepAlive = if let keepAliveInterval: UInt64 = (queryItems["keepaliveinterval"].flatMap { $0.value.flatMap { .init($0) } }),
                                      let keepAliveTimeout: UInt64 = (queryItems["keepalivetimeout"].flatMap { $0.value.flatMap { .init($0) } })
        {
            .init(intervalMs: keepAliveInterval, timeoutMs: keepAliveTimeout)
        } else {
            .default
        }

        let connectionName = queryItems["connectionanme"]?.value

        let secure: Bool = (queryItems["tls"].flatMap { $0.value.flatMap { .init($0) } }) ?? false

        let tlsVerifyCert: Bool = (queryItems["tlsverifycert"].flatMap { $0.value.flatMap { .init($0) } }) ?? false

        var cerificates: [TLSConfig.CertificateSource] = []
        if let tlsCaFilePath: String = queryItems["tlscafile"].flatMap(\.value) {
            if let cerificate = parseCertificate(path: tlsCaFilePath) {
                cerificates.append(cerificate)
            }
        }

        let defaultDeadline: Int = (queryItems["defaultdeadline"].flatMap { $0.value.flatMap { .init($0) } }) ?? .max

        return Self(
            clusterMode: clusterMode,
            cerificates: cerificates,
            nodePreference: nodePreference,
            gossipTimeout: gossipTimeout,
            secure: secure,
            tlsVerifyCert: tlsVerifyCert,
            defaultDeadline: defaultDeadline,
            connectionName: connectionName,
            keepAlive: keepAlive,
            authentication: authentication,
            discoveryInterval: discoveryInterval,
            maxDiscoveryAttempts: maxDiscoveryAttempts
        )
    }
}

extension ClientSettings {
    public static func parseCertificate(path: String) -> TLSConfig.CertificateSource? {
        do {
            let tlsCaFileUrl = URL(fileURLWithPath: path)
            let tlsCaFileData = try Data(contentsOf: tlsCaFileUrl)
            guard !tlsCaFileData.isEmpty else {
                logger.warning("tls ca file is empty.")
                return nil
            }

            let format: TLSConfig.SerializationFormat = if let tlsCaContent = String(data: tlsCaFileData, encoding: .ascii),
                                                           tlsCaContent.hasPrefix("-----BEGIN CERTIFICATE-----")
            {
                .pem
            } else {
                .der
            }

            return .file(path: path, format: format)

        } catch {
            logger.warning("tls ca file is not exist. error: \(error)")
            return nil
        }
    }
}

extension ClientSettings: ExpressibleByStringLiteral {
    public typealias StringLiteralType = String

    public init(stringLiteral value: String) {
        do {
            self = try Self.parse(connectionString: value)
        } catch let .internalParsingError(reason) {
            logger.error(.init(stringLiteral: reason))
            fatalError(reason)

        } catch {
            logger.error(.init(stringLiteral: "\(error)"))
            fatalError(error.localizedDescription)
        }
    }
}

extension ClientSettings: Buildable {
    @discardableResult
    public func cerificate(source: TLSConfig.CertificateSource) -> Self {
        withCopy {
            $0.cerificates.append(source)
        }
    }

    @discardableResult
    public func cerificate(path: String) -> Self {
        withCopy {
            if let cerificate = Self.parseCertificate(path: path) {
                $0.cerificates.append(cerificate)
            }
        }
    }

    @discardableResult
    public func secure(_ secure: Bool) -> Self {
        withCopy {
            $0.secure = secure
        }
    }

    @discardableResult
    public func tlsVerifyCert(_ tlsVerifyCert: Bool) -> Self {
        withCopy {
            $0.tlsVerifyCert = tlsVerifyCert
        }
    }

    @discardableResult
    public func defaultDeadline(_ defaultDeadline: Int) -> Self {
        withCopy {
            $0.defaultDeadline = defaultDeadline
        }
    }

    @discardableResult
    public func connectionName(_ connectionName: String) -> Self {
        withCopy {
            $0.connectionName = connectionName
        }
    }

    @discardableResult
    public func keepAlive(_ keepAlive: KeepAlive) -> Self {
        withCopy {
            $0.keepAlive = keepAlive
        }
    }

    @discardableResult
    public func authenticated(_ authenication: Authentication) -> Self {
        withCopy {
            $0.authentication = authenication
        }
    }

    @discardableResult
    public func discoveryInterval(_ discoveryInterval: Duration) -> Self {
        withCopy {
            $0.discoveryInterval = discoveryInterval
        }
    }

    @discardableResult
    public func maxDiscoveryAttempts(_ maxDiscoveryAttempts: UInt16) -> Self {
        withCopy {
            $0.maxDiscoveryAttempts = maxDiscoveryAttempts
        }
    }
}

extension ClientSettings {
    func makeClient(endpoint: Endpoint) throws(KurrentError) -> GRPCClient<HTTP2ClientTransport.Posix> {
        try withRethrowingError(usage: #function) {
            let transport: HTTP2ClientTransport.Posix = try .http2NIOPosix(
                target: endpoint.target,
                transportSecurity: transportSecurity
            )
            return GRPCClient<HTTP2ClientTransport.Posix>(transport: transport)
        }
    }

    var transportSecurity: HTTP2ClientTransport.Posix.TransportSecurity {
        if secure {
            .tls { config in
                if let trustRoots {
                    config.trustRoots = trustRoots
                }
            }
        } else {
            .plaintext
        }
    }
}
