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

/// Default environment variable name consulted by ``ClientSettings/fromEnv(key:)``.
public let DEFAULT_ENV_KEY_NAME: String = "SWIFT_KURRENT_DB_URL"

/// Connection and transport configuration for a KurrentDB client.

public struct ClientSettings: Sendable {
    /// Resolved server endpoints derived from the cluster mode.
    public private(set) var endpoints: [Endpoint]
    /// TLS certificate sources used to verify the server.
    public var certificates: [TLSConfig.CertificateSource]

    /// Set by the deprecated ``certificate(path:)`` when its file cannot be read. The client then
    /// refuses to connect and ``trustRoots`` never falls back to the system roots.
    package var hasUnreadableCertificate: Bool = false

    /// Reason carried by the `initializationError` thrown while ``hasUnreadableCertificate`` is set.
    package static let unreadableCertificateRefusalReason = "A CA certificate file passed to certificate(path:) cannot be read; refusing to fall back to the system trust roots."

    /// Whether DNS-based cluster discovery is active.
    public private(set) var dnsDiscover: Bool
    /// Preferred node role to connect to in a cluster.
    public private(set) var nodePreference: NodePreference
    /// Maximum time allowed for a gossip request to complete.
    public private(set) var gossipTimeout: Duration
    /// Which endpoint to connect through once gossip selects a node.
    public var endpointResolutionPreference: EndpointResolutionPreference

    /// Whether TLS is enabled for the connection.
    public private(set) var secure: Bool
    /// Whether server certificate verification is enforced when TLS is active.
    public private(set) var tlsVerifyCert: Bool

    /// Default deadline in milliseconds for calls that complete before they return (single
    /// responses, appends, buffered reads, batch appends); `.max` means no deadline. Subscriptions,
    /// persistent-subscription reads, server statistics and `read().lazy` are not bounded by it, and
    /// a `CallOptions.timeout` set on the client wins.
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
    ///
    /// Defaults to 2 attempts with no delay (one immediate retry), which covers a leader change
    /// that has already completed when the first call fails. To ride out an election still in
    /// progress, opt into ``OperationRetryPolicy/default`` or a custom policy with backoff.
    public var operationRetryPolicy: OperationRetryPolicy

    /// Creates settings with explicit values for all configurable options.
    ///
    /// - Parameters:
    ///   - clusterMode: Topology describing how to reach the server. Defaults to `nil` (no endpoint configured).
    ///   - certificates: TLS certificate sources for server verification. Defaults to empty.
    ///   - nodePreference: Preferred node role in a cluster. Defaults to `.leader`.
    ///   - gossipTimeout: Timeout for gossip requests. Defaults to 3 seconds.
    ///   - endpointResolutionPreference: Which endpoint to connect through once gossip selects
    ///     a node. Defaults to `.gossipReported`.
    ///   - secure: Enables TLS. Defaults to `true`.
    ///   - tlsVerifyCert: Enables certificate verification when TLS is active. Defaults to `true`.
    ///   - defaultDeadline: Deadline in milliseconds for calls that complete before they return; see
    ///     ``defaultDeadline``. Defaults to `.max` (no deadline).
    ///   - connectionName: Optional label for this connection.
    ///   - keepAlive: Keep-alive timing. Defaults to `.default`.
    ///   - authentication: Credentials or certificate for authentication.
    ///   - discoveryInterval: Interval between discovery polls. Defaults to 100 ms.
    ///   - maxDiscoveryAttempts: Maximum discovery retries. Defaults to 10.
    ///   - nodeCacheTTL: How long to cache a discovered node. Defaults to 30 seconds.
    ///   - operationRetryPolicy: Retry behaviour for node-failure errors. Defaults to 2 attempts
    ///     with no delay; ``OperationRetryPolicy/default`` adds backoff and jitter.
    public init(
        clusterMode: TopologyClusterMode? = nil,
        certificates: [TLSConfig.CertificateSource] = [],
        nodePreference: NodePreference = .leader,
        gossipTimeout: Duration = .seconds(3),
        endpointResolutionPreference: EndpointResolutionPreference = .gossipReported,
        secure: Bool = true,
        tlsVerifyCert: Bool = true,
        defaultDeadline: Int = .max,
        connectionName: String? = nil,
        keepAlive: KeepAlive = .default,
        authentication: Authentication? = nil,
        discoveryInterval: Duration = .milliseconds(100),
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
        self.endpointResolutionPreference = endpointResolutionPreference
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
        // A CA that was named but could not be read must not become "trust the system roots".
        return if certificates.isEmpty && !hasUnreadableCertificate {
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

    /// Parses with ``RFC3986Policy`` (`.rfc3986`); see ``parse(connectionString:policy:)``.
    public static func parse(connectionString: String) throws(KurrentError) -> Self {
        try parse(connectionString: connectionString, policy: .rfc3986)
    }

    /// Parses a KurrentDB connection string into `ClientSettings`.
    ///
    /// Supported schemes are `kurrentdb`, `kurrent`, `kdb` and `esdb`, each also with `+discover`
    /// (case-insensitive). Recognised query parameters are
    /// `tls`, `tlsVerifyCert`, `nodePreference`, `keepAliveInterval` and `keepAliveTimeout` (both
    /// required for either to take effect), `gossipTimeout`, `maxDiscoverAttempts`, `discoveryInterval`,
    /// `userCertFile`, `userKeyFile`, `connectionName`, `tlsCaFile`, and `defaultDeadline`; any other
    /// parameter throws.
    ///
    /// ```swift
    /// let settings = try ClientSettings.parse(
    ///     connectionString: "esdb://admin:changeit@localhost:2113?tls=false"
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - connectionString: A well-formed KurrentDB connection string. Leading and trailing
    ///     whitespace and newlines are ignored.
    ///   - policy: The parsing rules to apply. ``RFC3986Policy`` requires
    ///     `@ / ? # %` in credentials and `@ # %` in parameter values to be percent-encoded, as well
    ///     as whitespace and non-ASCII characters anywhere. Parameter values may contain `/` and `?`.
    /// - Returns: Fully populated `ClientSettings`.
    /// - Throws: `KurrentError.internalParsingError` if the string is malformed, lacks a host, or has an unknown, duplicate or invalid parameter. The reason names the component or parameter, never its value.
    public static func parse(connectionString: String, policy: RFC3986Policy) throws(KurrentError) -> Self {
        let parsed = try ConnectionString(
            parsing: connectionString.trimmingCharacters(in: .whitespacesAndNewlines),
            policy: policy
        )
        let parameters = try ConnectionStringParameters(parsed.parameters)

        let clusterMode: TopologyClusterMode = if parsed.scheme == .dnsDiscover {
            .dns(domain: parsed.endpoints[0])
        } else if parsed.endpoints.count > 1 {
            .seeds(parsed.endpoints)
        } else {
            .standalone(endpoint: parsed.endpoints[0])
        }

        let nodePreference: NodePreference
        if let raw = try parameters.string("nodepreference") {
            guard let preference = NodePreference(rawValue: raw.lowercased()) else {
                throw .internalParsingError(reason: "Parameter 'nodepreference' must be leader, follower, random or readOnlyReplica.")
            }
            nodePreference = preference
        } else {
            nodePreference = .leader
        }

        let gossipTimeout = try parameters.duration("gossiptimeout", unit: .seconds) ?? .seconds(5)
        let maxDiscoveryAttempts = try parameters.positiveInteger("maxdiscoverattempts", as: UInt16.self) ?? 10
        let discoveryInterval = try parameters.duration("discoveryinterval", unit: .milliseconds) ?? .milliseconds(100)

        let certFile = try parameters.string("usercertfile")
        let keyFile = try parameters.string("userkeyfile")
        let authentication: Authentication?
        switch (certFile, keyFile) {
        case let (certFile?, keyFile?):
            authentication = .x509(certFile: certFile, keyFile: keyFile)
        case (nil, nil):
            authentication = parsed.credentials.map { .credentials(username: $0.username, password: $0.password) }
        default:
            throw .internalParsingError(reason: "Parameters 'usercertfile' and 'userkeyfile' must be given together.")
        }

        // Connection string values are in seconds. Only both together replace the default.
        let keepAliveInterval = try parameters.duration("keepaliveinterval", unit: .seconds)
        let keepAliveTimeout = try parameters.duration("keepalivetimeout", unit: .seconds)
        let keepAlive: KeepAlive = if let keepAliveInterval, let keepAliveTimeout {
            .init(interval: keepAliveInterval, timeout: keepAliveTimeout)
        } else {
            .default
        }

        let connectionName = try parameters.string("connectionname")
        let secure = try parameters.bool("tls") ?? true

        // The client certificate is presented in the TLS handshake, so X.509 needs TLS.
        if case .x509 = authentication, !secure {
            throw .internalParsingError(reason: "X.509 authentication (userCertFile/userKeyFile) requires a TLS connection; remove tls=false.")
        }

        let tlsVerifyCert = try parameters.bool("tlsverifycert") ?? true

        var certificates: [TLSConfig.CertificateSource] = []
        if let tlsCaFilePath = try parameters.string("tlscafile") {
            // A CA the caller named but the client cannot read must not quietly become "trust the
            // system roots".
            guard let certificate = readableCertificate(path: tlsCaFilePath) else {
                throw .internalParsingError(reason: "Parameter 'tlsCaFile' names a CA file that cannot be read.")
            }
            certificates.append(certificate)
        }

        // Validated as a duration so a deadline computed from it cannot overflow; stored in ms.
        let defaultDeadline: Int = if let milliseconds = try parameters.milliseconds("defaultdeadline") {
            milliseconds
        } else {
            .max
        }

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

    /// Parses with ``RFC3986Policy`` (`.rfc3986`); see ``fromEnv(key:policy:)``.
    public static func fromEnv(key: String = DEFAULT_ENV_KEY_NAME) throws(KurrentError) -> Self {
        try fromEnv(key: key, policy: .rfc3986)
    }

    /// Builds `ClientSettings` by parsing a KurrentDB connection string read from an environment variable.
    ///
    /// ```swift
    /// // Reads from SWIFT_KURRENT_DB_URL by default.
    /// let settings = try ClientSettings.fromEnv()
    ///
    /// // Or read from a custom environment variable.
    /// let customSettings = try ClientSettings.fromEnv(key: "MY_KURRENTDB_URL")
    /// ```
    ///
    /// - Parameters:
    ///   - key: Name of the environment variable holding the connection string. Defaults to `DEFAULT_ENV_KEY_NAME` (`"SWIFT_KURRENT_DB_URL"`).
    ///   - policy: The parsing rules to apply; see ``ClientSettings/parse(connectionString:policy:)``. Trailing newlines in the variable (common with mounted secrets) are ignored.
    /// - Returns: Fully populated `ClientSettings`.
    /// - Throws: `KurrentError.internalParsingError` if the environment variable is unset or the connection string is malformed.
    public static func fromEnv(key: String = DEFAULT_ENV_KEY_NAME, policy: RFC3986Policy) throws(KurrentError) -> Self {
        guard let connectionString = ProcessInfo.processInfo.environment[key] else {
            throw KurrentError.internalParsingError(reason: "Environment variable \(key) is not set")
        }
        return try parse(connectionString: connectionString, policy: policy)
    }
}

extension ClientSettings {
    /// Loads a TLS CA certificate from disk and returns the appropriate source.
    ///
    /// Detects PEM format automatically by inspecting the file header; falls back to DER.
    /// Returns `nil` and logs a warning if the file is missing or empty.
    ///
    /// - Important: A `nil` result must not be ignored. Appending nothing makes ``trustRoots`` fall
    ///   back to the system roots; prefer ``certificate(path:fallback:)``.
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

    /// A certificate source for a CA file the client can actually read, or nil when the file is
    /// missing, not readable, a directory, or empty. Logs nothing: each caller reports the failure
    /// in its own way, without the path.
    package static func readableCertificate(path: String) -> TLSConfig.CertificateSource? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), !data.isEmpty else {
            return nil
        }
        let isPEM = String(data: data.prefix(27), encoding: .ascii) == "-----BEGIN CERTIFICATE-----"
        return .file(path: path, format: isPEM ? .pem : .der)
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

    /// Returns a copy with a CA certificate loaded from a file appended.
    ///
    /// - Parameters:
    ///   - path: File-system path to the certificate (PEM or DER).
    ///   - fallback: What to do when the file is missing, not readable or empty. `.none` throws;
    ///     `.systemTrustRoots` leaves it out, so the system's root certificates are trusted if no
    ///     other CA is configured. There is no default on purpose.
    /// - Throws: `KurrentError.initializationError` when the file cannot be read and `fallback` is `.none`.
    @discardableResult
    public func certificate(path: String, fallback: CertificateFallback) throws(KurrentError) -> Self {
        if let certificate = Self.readableCertificate(path: path) {
            return withCopy { $0.certificates.append(certificate) }
        }
        switch fallback {
        case .none:
            throw .initializationError(reason: "The CA certificate file passed to certificate(path:fallback:) cannot be read.")
        case .systemTrustRoots:
            logger.warning("Configured CA certificate file is unreadable; leaving it out as requested (fallback: .systemTrustRoots) — the system trust roots apply if no other CA is configured.")
            return self
        }
    }

    /// Returns a copy with a certificate loaded from the given file path appended.
    ///
    /// When the file cannot be read it is not silently replaced by the system trust roots: the
    /// client refuses to connect with `KurrentError.initializationError`.
    ///
    /// - Parameter path: File-system path to the certificate file.
    @available(*, deprecated, message: "Use certificate(path:fallback:), which reports an unreadable file instead of widening trust.")
    @discardableResult
    public func certificate(path: String) -> Self {
        withCopy {
            if let certificate = Self.readableCertificate(path: path) {
                $0.certificates.append(certificate)
            } else {
                $0.hasUnreadableCertificate = true
                logger.warning("A CA certificate file passed to certificate(path:) cannot be read; the client will refuse to connect. Use certificate(path:fallback:).")
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

    /// Deprecated. Use ``certificate(path:fallback:)`` instead.
    @available(*, deprecated, message: "Use certificate(path:fallback:).")
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

    /// Returns a copy with the endpoint resolution preference set.
    ///
    /// - Parameter preference: `.gossipReported` (default) connects through the address
    ///   gossip reports — required for `.seeds` / `.dns`. `.userConfigured` always connects
    ///   through the endpoint you configured — safe only for `.standalone`.
    @discardableResult
    public func endpointResolutionPreference(_ preference: EndpointResolutionPreference) -> Self {
        withCopy {
            $0.endpointResolutionPreference = preference
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
        secure ? .tls(tlsConfiguration) : .plaintext
    }

    /// TLS settings for a secure connection.
    ///
    /// With ``Authentication/x509(certFile:keyFile:)`` the client certificate and key are offered
    /// during the TLS handshake — that is how the server learns who the user is, since X.509
    /// sends no `Authorization` header.
    var tlsConfiguration: HTTP2ClientTransport.Posix.TransportSecurity.TLS {
        var config = HTTP2ClientTransport.Posix.TransportSecurity.TLS.defaults
        if let trustRoots {
            config.trustRoots = trustRoots
        }
        config.serverCertificateVerification = tlsVerifyCert ? .fullVerification : .noVerification
        if case let .x509(certFile, keyFile) = authentication {
            config.certificateChain = [.file(path: certFile, format: .pem)]
            config.privateKey = .file(path: keyFile, format: .pem)
        }
        return config
    }
}

/// Typed, validated access to a connection string's query parameters.
///
/// Every getter returns nil for an absent parameter and throws for a present but malformed one,
/// naming the parameter, never its value.
private struct ConnectionStringParameters {
    enum DurationUnit {
        case seconds, milliseconds

        var nanoseconds: Int64 {
            switch self {
            case .seconds: 1_000_000_000
            case .milliseconds: 1_000_000
            }
        }
    }

    static let known: Set<String> = [
        "tls", "tlsverifycert", "tlscafile", "connectionname", "nodepreference",
        "gossiptimeout", "maxdiscoverattempts", "discoveryinterval", "defaultdeadline",
        "keepaliveinterval", "keepalivetimeout", "usercertfile", "userkeyfile",
    ]

    private let values: [String: String]

    init(_ values: [String: String]) throws(KurrentError) {
        if let unknown = values.keys.sorted().first(where: { !Self.known.contains($0) }) {
            throw .internalParsingError(reason: "Unknown connection string parameter '\(ConnectionString.displayName(unknown))'.")
        }
        self.values = values
    }

    func string(_ key: String) throws(KurrentError) -> String? {
        guard let value = values[key] else { return nil }
        guard !value.isEmpty else {
            throw .internalParsingError(reason: "Parameter '\(key)' must not be empty.")
        }
        return value
    }

    func bool(_ key: String) throws(KurrentError) -> Bool? {
        guard let value = values[key] else { return nil }
        switch value.lowercased() {
        case "true": return true
        case "false": return false
        default: throw .internalParsingError(reason: "Parameter '\(key)' must be true or false.")
        }
    }

    func positiveInteger<T: FixedWidthInteger>(_ key: String, as _: T.Type) throws(KurrentError) -> T? {
        guard let value = values[key] else { return nil }
        guard let number = T(value), number > 0 else {
            throw .internalParsingError(reason: "Parameter '\(key)' must be a positive integer no larger than \(T.max).")
        }
        return number
    }

    /// A positive duration whose nanosecond value fits in `Int64`, so nothing downstream
    /// (NIO `TimeAmount`, deadline arithmetic) can overflow.
    func duration(_ key: String, unit: DurationUnit) throws(KurrentError) -> Duration? {
        guard let number = try boundedNumber(key, unit: unit) else { return nil }
        return switch unit {
        case .seconds: .seconds(number)
        case .milliseconds: .milliseconds(number)
        }
    }

    /// A positive millisecond count that fits in `Int` on this platform (32-bit included) and
    /// whose nanosecond value fits in `Int64`.
    func milliseconds(_ key: String) throws(KurrentError) -> Int? {
        guard let number = try boundedNumber(key, unit: .milliseconds) else { return nil }
        guard let milliseconds = Int(exactly: number) else {
            throw .internalParsingError(reason: "Parameter '\(key)' must be a positive integer within range.")
        }
        return milliseconds
    }

    private func boundedNumber(_ key: String, unit: DurationUnit) throws(KurrentError) -> Int64? {
        guard let value = values[key] else { return nil }
        guard let number = Int64(value), number > 0,
              !number.multipliedReportingOverflow(by: unit.nanoseconds).overflow
        else {
            throw .internalParsingError(reason: "Parameter '\(key)' must be a positive integer within range.")
        }
        return number
    }
}
