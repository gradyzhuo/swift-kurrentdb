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

/// Default TCP port number for KurrentDB connections.
public let DEFAULT_PORT_NUMBER: UInt32 = 2113

/// Connection and transport configuration for a KurrentDB client.

public struct ClientSettings: Sendable {
    /// Resolved server endpoints derived from the cluster mode.
    public private(set) var endpoints: [Endpoint]
    /// TLS certificate sources used to verify the server.
    public var certificates: [TLSConfig.CertificateSource]

    /// Whether DNS-based cluster discovery is active.
    public private(set) var dnsDiscover: Bool
    /// Preferred node role to connect to in a cluster.
    public private(set) var nodePreference: NodePreference
    /// Maximum time allowed for a gossip request to complete.
    public private(set) var gossipTimeout: Duration

    /// Whether TLS is enabled for the connection.
    public private(set) var secure: Bool
    /// Whether server certificate verification is enforced when TLS is active.
    public private(set) var tlsVerifyCert: Bool

    /// Default operation deadline in milliseconds; `.max` means no deadline.
    public private(set) var defaultDeadline: Int
    /// Optional human-readable label for this connection.
    public private(set) var connectionName: String?

    /// Keep-alive timing configuration for the gRPC channel.
    public var keepAlive: KeepAlive
    /// Authentication credentials or certificate sent with each request.
    public var authentication: Authentication?
    /// Interval between cluster node discovery polls.
    public var discoveryInterval: Duration
    /// Maximum number of node discovery attempts before giving up.
    public var maxDiscoveryAttempts: UInt16
    /// Duration for which a discovered node is cached before re-validation.
    public var nodeCacheTTL: Duration
    /// Retry policy applied to operations that fail due to node-level errors.
    public var operationRetryPolicy: OperationRetryPolicy

    /// Creates settings with explicit values for all configurable options.
    ///
    /// - Parameters:
    ///   - clusterMode: Topology describing how to reach the server. Defaults to `nil` (no endpoint configured).
    ///   - certificates: TLS certificate sources for server verification. Defaults to empty.
    ///   - nodePreference: Preferred node role in a cluster. Defaults to `.leader`.
    ///   - gossipTimeout: Timeout for gossip requests. Defaults to 3 seconds.
    ///   - secure: Enables TLS. Defaults to `true`.
    ///   - tlsVerifyCert: Enables certificate verification when TLS is active. Defaults to `true`.
    ///   - defaultDeadline: Operation deadline in milliseconds. Defaults to `.max`.
    ///   - connectionName: Optional label for this connection.
    ///   - keepAlive: Keep-alive timing. Defaults to `.default`.
    ///   - authentication: Credentials or certificate for authentication.
    ///   - discoveryInterval: Interval between discovery polls. Defaults to 100 µs.
    ///   - maxDiscoveryAttempts: Maximum discovery retries. Defaults to 10.
    ///   - nodeCacheTTL: How long to cache a discovered node. Defaults to 30 seconds.
    ///   - operationRetryPolicy: Retry behaviour for node-failure errors.
    public init(
        clusterMode: TopologyClusterMode? = nil,
        certificates: [TLSConfig.CertificateSource] = [],
        nodePreference: NodePreference = .leader,
        gossipTimeout: Duration = .seconds(3),
        secure: Bool = true,
        tlsVerifyCert: Bool = true,
        defaultDeadline: Int = .max,
        connectionName: String? = nil,
        keepAlive: KeepAlive = .default,
        authentication: Authentication? = nil,
        discoveryInterval: Duration = .microseconds(100),
        maxDiscoveryAttempts: UInt16 = 10,
        nodeCacheTTL: Duration = .seconds(30),
        operationRetryPolicy: OperationRetryPolicy = OperationRetryPolicy(
            maxAttempts: 2,
            initialDelay: .zero,
            maxDelay: .zero,
            multiplier: 1.0,
            jitter: .none
        )
    ) {
        self.certificates = certificates
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
        self.nodeCacheTTL = nodeCacheTTL
        self.operationRetryPolicy = operationRetryPolicy

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
    /// Cluster topology derived from the current endpoints and discovery mode.
    public var clusterMode: TopologyClusterMode {
        if dnsDiscover {
            .dns(domain: endpoints[0])
        } else if endpoints.count > 1 {
            .seeds(endpoints)
        } else {
            .standalone(endpoint: endpoints[0])
        }
    }

    /// TLS trust-roots source derived from `certificates`; `nil` when TLS is disabled.
    public var trustRoots: TLSConfig.TrustRootsSource? {
        guard secure else {
            return nil
        }
        return if certificates.isEmpty {
            .systemDefault
        } else {
            .certificates(certificates)
        }
    }

    /// Builds an HTTP or HTTPS URL for the given endpoint using the current security mode.
    ///
    /// - Parameter endpoint: The target endpoint.
    /// - Returns: A `URL` for the endpoint, or `nil` if the URL components are invalid.
    public func httpUri(endpoint: Endpoint) -> URL? {
        var components = URLComponents()
        components.scheme = secure ? "https" : "http"
        components.host = endpoint.host
        components.port = Int(endpoint.port)
        return components.url
    }
}

extension ClientSettings {
    /// Returns settings targeting a single insecure KurrentDB node on `localhost:2113`.
    ///
    /// ```swift
    /// let settings = ClientSettings.localhost()
    ///     .authenticated(.credentials(username: "admin", password: "changeit"))
    /// ```
    ///
    /// - Returns: Insecure `ClientSettings` for `localhost` on the default port.
    public static func localhost() -> Self {
        localhost(ports: DEFAULT_PORT_NUMBER)
    }

    /// Returns insecure settings targeting one or more ports on `localhost`.
    ///
    /// - Parameter ports: One or more port numbers. Multiple ports produce a seed-cluster topology.
    /// - Returns: Insecure `ClientSettings` for the given `localhost` ports.
    public static func localhost(ports: UInt32...) -> Self {
        let endpoints: [Endpoint] = ports.map { .init(host: "localhost", port: $0) }
        let clusterMode: TopologyClusterMode = if endpoints.count == 1 {
            .standalone(endpoint: endpoints[0])
        } else {
            .seeds(endpoints)
        }
        return Self(clusterMode: clusterMode, secure: false, tlsVerifyCert: false)
    }

    /// Returns settings targeting one or more remote endpoints.
    ///
    /// - Parameters:
    ///   - endpoints: One or more server endpoints. Multiple endpoints produce a seed-cluster topology.
    ///   - secure: Enables TLS. Defaults to `true`.
    /// - Returns: `ClientSettings` configured for the provided remote endpoints.
    public static func remote(_ endpoints: Endpoint..., secure: Bool = true) -> Self {
        let clusterMode: TopologyClusterMode = if endpoints.count == 1 {
            .standalone(endpoint: endpoints[0])
        } else {
            .seeds(endpoints)
        }
        return Self(clusterMode: clusterMode, secure: secure)
    }

    /// Parses a KurrentDB connection string into `ClientSettings`.
    ///
    /// Supported schemes are `esdb://` and `esdb+discover://`. Recognised query parameters include
    /// `tls`, `tlsVerifyCert`, `nodePreference`, `keepAliveInterval` and `keepAliveTimeout` (both
    /// required for either to take effect), `gossipTimeout`, `maxDiscoverAttempts`, `discoveryInterval`,
    /// `userCertFile`, `userKeyFile`, `connectionName`, `tlsCaFile`, and `defaultDeadline`.
    ///
    /// ```swift
    /// let settings = try ClientSettings.parse(
    ///     connectionString: "esdb://admin:changeit@localhost:2113?tls=false"
    /// )
    /// ```
    ///
    /// - Parameter connectionString: A well-formed KurrentDB connection string.
    /// - Returns: Fully populated `ClientSettings`.
    /// - Throws: `KurrentError.internalParsingError` if the string is malformed or missing required components.
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
            NodePreference(rawValue: $0.lowercased())
        } ?? .leader

        let gossipTimeout: Duration = queryItems["gossiptimeout"]
            .flatMap({ $0.value.flatMap { Int64($0) } })
            .map { .seconds($0) } ?? .seconds(5)

        let maxDiscoveryAttempts: UInt16 = queryItems["maxdiscoverattempts"]
            .flatMap({ $0.value.flatMap { UInt16($0) } }) ?? 10

        let discoveryInterval: Duration = queryItems["discoveryinterval"]
            .flatMap({ $0.value.flatMap { Int64($0) } })
            .map { .milliseconds($0) } ?? .milliseconds(100)

        let authentication: Authentication?
        if let certFile = queryItems["usercertfile"].flatMap(\.value),
           let keyFile = queryItems["userkeyfile"].flatMap(\.value)
        {
            authentication = .x509(certFile: certFile, keyFile: keyFile)
        } else {
            authentication = userCredentialParser.parse(connectionString)
        }

        let keepAlive: KeepAlive = if let keepAliveInterval: UInt64 = (queryItems["keepaliveinterval"].flatMap { $0.value.flatMap { .init($0) } }),
                                      let keepAliveTimeout: UInt64 = (queryItems["keepalivetimeout"].flatMap { $0.value.flatMap { .init($0) } })
        {
            // Connection string values are in seconds; convert to milliseconds
            .init(intervalMs: keepAliveInterval * 1000, timeoutMs: keepAliveTimeout * 1000)
        } else {
            .default
        }

        let connectionName = queryItems["connectionname"]?.value

        let secure: Bool = (queryItems["tls"].flatMap { $0.value.flatMap { .init($0) } }) ?? true

        let tlsVerifyCert: Bool = (queryItems["tlsverifycert"].flatMap { $0.value.flatMap { .init($0) } }) ?? true

        var certificates: [TLSConfig.CertificateSource] = []
        if let tlsCaFilePath: String = queryItems["tlscafile"].flatMap(\.value) {
            if let certificate = parseCertificate(path: tlsCaFilePath) {
                certificates.append(certificate)
            }
        }

        let defaultDeadline: Int = (queryItems["defaultdeadline"].flatMap { $0.value.flatMap { .init($0) } }) ?? .max

        return Self(
            clusterMode: clusterMode,
            certificates: certificates,
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
    /// Loads a TLS CA certificate from disk and returns the appropriate source.
    ///
    /// Detects PEM format automatically by inspecting the file header; falls back to DER.
    /// Returns `nil` and logs a warning if the file is missing or empty.
    ///
    /// - Parameter path: File-system path to the CA certificate.
    /// - Returns: A `TLSConfig.CertificateSource` for the file, or `nil` on failure.
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
    /// String literal type for `ExpressibleByStringLiteral` conformance.
    public typealias StringLiteralType = String

    /// Creates `ClientSettings` by parsing a KurrentDB connection string literal.
    ///
    /// - Parameter value: A well-formed KurrentDB connection string (e.g. `"esdb://localhost:2113"`).
    ///
    /// > Important: Calls `fatalError` if `value` is not a valid connection string.
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
    /// Returns a copy with the given certificate source appended.
    ///
    /// - Parameter source: The certificate source to add.
    @discardableResult
    public func certificate(source: TLSConfig.CertificateSource) -> Self {
        withCopy {
            $0.certificates.append(source)
        }
    }

    /// Returns a copy with a certificate loaded from the given file path appended.
    ///
    /// - Parameter path: File-system path to the certificate file.
    @discardableResult
    public func certificate(path: String) -> Self {
        withCopy {
            if let certificate = Self.parseCertificate(path: path) {
                $0.certificates.append(certificate)
            }
        }
    }

    /// Deprecated. Use ``certificates`` instead.
    @available(*, deprecated, renamed: "certificates")
    public var cerificates: [TLSConfig.CertificateSource] {
        get { certificates }
        set { certificates = newValue }
    }

    /// Deprecated. Use ``certificate(source:)`` instead.
    @available(*, deprecated, renamed: "certificate(source:)")
    @discardableResult
    public func cerificate(source: TLSConfig.CertificateSource) -> Self {
        certificate(source: source)
    }

    /// Deprecated. Use ``certificate(path:)`` instead.
    @available(*, deprecated, renamed: "certificate(path:)")
    @discardableResult
    public func cerificate(path: String) -> Self {
        certificate(path: path)
    }

    /// Returns a copy with TLS enabled or disabled.
    ///
    /// - Parameter secure: Pass `true` to enable TLS, `false` for plaintext.
    @discardableResult
    public func secure(_ secure: Bool) -> Self {
        withCopy {
            $0.secure = secure
        }
    }

    /// Returns a copy with certificate verification enabled or disabled.
    ///
    /// - Parameter tlsVerifyCert: Pass `true` to enforce full certificate verification.
    @discardableResult
    public func tlsVerifyCert(_ tlsVerifyCert: Bool) -> Self {
        withCopy {
            $0.tlsVerifyCert = tlsVerifyCert
        }
    }

    /// Returns a copy with the default operation deadline set.
    ///
    /// - Parameter defaultDeadline: Deadline in milliseconds; use `.max` for no deadline.
    @discardableResult
    public func defaultDeadline(_ defaultDeadline: Int) -> Self {
        withCopy {
            $0.defaultDeadline = defaultDeadline
        }
    }

    /// Returns a copy with the given connection name set.
    ///
    /// - Parameter connectionName: Human-readable label for this connection.
    @discardableResult
    public func connectionName(_ connectionName: String) -> Self {
        withCopy {
            $0.connectionName = connectionName
        }
    }

    /// Returns a copy with the given keep-alive settings applied.
    ///
    /// - Parameter keepAlive: Keep-alive interval and timeout configuration.
    @discardableResult
    public func keepAlive(_ keepAlive: KeepAlive) -> Self {
        withCopy {
            $0.keepAlive = keepAlive
        }
    }

    /// Returns a copy with the given authentication applied.
    ///
    /// - Parameter authenication: Credentials or certificate used for authentication.
    @discardableResult
    public func authenticated(_ authenication: Authentication) -> Self {
        withCopy {
            $0.authentication = authenication
        }
    }

    /// Returns a copy with the cluster discovery interval set.
    ///
    /// - Parameter discoveryInterval: Time between consecutive discovery polls.
    @discardableResult
    public func discoveryInterval(_ discoveryInterval: Duration) -> Self {
        withCopy {
            $0.discoveryInterval = discoveryInterval
        }
    }

    /// Returns a copy with the maximum discovery attempts set.
    ///
    /// - Parameter maxDiscoveryAttempts: Upper limit on node-discovery retries.
    @discardableResult
    public func maxDiscoveryAttempts(_ maxDiscoveryAttempts: UInt16) -> Self {
        withCopy {
            $0.maxDiscoveryAttempts = maxDiscoveryAttempts
        }
    }

    /// Returns a copy with the node cache TTL set.
    ///
    /// - Parameter ttl: Duration for which a discovered node is cached before re-validation.
    @discardableResult
    public func nodeCacheTTL(_ ttl: Duration) -> Self {
        withCopy {
            $0.nodeCacheTTL = ttl
        }
    }

    /// Returns a copy with the operation retry policy set.
    ///
    /// - Parameter policy: Retry behaviour applied to node-failure errors.
    @discardableResult
    public func operationRetryPolicy(_ policy: OperationRetryPolicy) -> Self {
        withCopy {
            $0.operationRetryPolicy = policy
        }
    }
}

extension ClientSettings {
    var transportSecurity: HTTP2ClientTransport.Posix.TransportSecurity {
        if secure {
            .tls { config in
                if let trustRoots {
                    config.trustRoots = trustRoots
                }
                config.serverCertificateVerification = tlsVerifyCert ? .fullVerification : .noVerification
            }
        } else {
            .plaintext
        }
    }
}
