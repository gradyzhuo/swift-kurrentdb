//
//  ClientSettings.swift
//  KurrentCore
//
//  Created by Grady Zhuo on 2023/10/17.
//

import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import Logging
import NIOCore
import NIOPosix
import NIOSSL
import RegexBuilder
import GRPCEncapsulates
import NIOTransportServices

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
    
    public init(){
        self.endpoints = []
        self.cerificates = []
        self.dnsDiscover = false
        self.nodePreference = .leader
        self.gossipTimeout = .seconds(3)
        self.secure = false
        self.tlsVerifyCert = false
        self.defaultDeadline = .max
        self.keepAlive = .default
        self.discoveryInterval = .microseconds(100)
        self.maxDiscoveryAttempts = 10
    }

}

extension ClientSettings {
    public var clusterMode: TopologyClusterMode{
        return if dnsDiscover {
            .dns(domain: endpoints[0])
        }else if endpoints.count > 1 {
            .seeds(endpoints)
        }else{
            .standalone(endpoint: endpoints[0])
        }
    }
    
    public var trustRoots: TLSConfig.TrustRootsSource?{
        get{
            guard secure else {
                return nil
            }
            return if cerificates.isEmpty {
                .systemDefault
            }else{
                .certificates(cerificates)
            }
        }
    }
    
    public func httpUri(endpoint: Endpoint) -> URL? {
        var components = URLComponents()
        components.scheme = self.secure ? "https" : "http"
        components.host = endpoint.host
        components.port = Int(endpoint.port)
        return components.url
    }
}

extension ClientSettings {
    public static func localhost(port: UInt32 = DEFAULT_PORT_NUMBER) -> Self {
        var settings = Self.init()
        settings.endpoints = [
            .init(host: "localhost", port: port)
        ]
        return settings
    }

    public static func parse(connectionString: String) throws(KurrentError) -> Self {
        let schemeParser = URLSchemeParser()
        let endpointParser = EndpointParser()
        let queryItemParser = QueryItemParser()
        let userCredentialParser = UserCredentialsParser()
        
        guard let scheme = schemeParser.parse(connectionString) else {
            throw KurrentError.internalParsingError(reason: "Unknown URL scheme: \(connectionString)")
        }

        var settings = Self.init()
        
        guard let endpoints = endpointParser.parse(connectionString),
              endpoints.count > 0
        else {
            throw KurrentError.internalParsingError(reason: "Connection string doesn't have an host")
        }
        
        guard endpoints.count > 0 else {
            throw .internalParsingError(reason: "empty endpoint.")
        }
        
        settings.endpoints = endpoints

        let parsedResult = queryItemParser.parse(connectionString) ?? []

        let queryItems: [String: URLQueryItem] = .init(uniqueKeysWithValues: parsedResult.map {
            ($0.name.lowercased(), $0)
        })
        
        settings.dnsDiscover = scheme == .dnsDiscover
        
        if let nodePreference = queryItems["nodepreference"]?.value.flatMap({
            NodePreference(rawValue: $0)
        }){
            settings.nodePreference = nodePreference
        }
        
        if let gossipTimeout: Int64 = queryItems["gossiptimeout"].flatMap({ $0.value.flatMap { Int64($0) } }){
            settings.gossipTimeout = .microseconds(gossipTimeout)
        }
        
        
        if let maxDiscoverAttempts = queryItems["maxdiscoverattempts"].flatMap({ $0.value.flatMap { UInt16($0) } }) {
            settings.maxDiscoveryAttempts = maxDiscoverAttempts
        }
        
        if let discoverInterval = queryItems["discoveryinterval"].flatMap({ $0.value.flatMap { Int64($0) } }){
            settings.discoveryInterval = .microseconds(discoverInterval)
        }
        
        if let authentication = userCredentialParser.parse(connectionString) {
            settings.authentication = authentication
        }

        if let keepAliveInterval: UInt64 = (queryItems["keepaliveinterval"].flatMap { $0.value.flatMap { .init($0) } }),
           let keepAliveTimeout: UInt64 = (queryItems["keepalivetimeout"].flatMap { $0.value.flatMap { .init($0) } })
        {
            settings.keepAlive = .init(intervalMs: keepAliveInterval, timeoutMs: keepAliveTimeout)
        }

        if let connectionName = queryItems["connectionanme"]?.value {
            settings.connectionName = connectionName
        }
        
        if let secure: Bool = (queryItems["tls"].flatMap { $0.value.flatMap { .init($0) } }) {
            settings.secure = secure
        }

        if let tlsVerifyCert: Bool = (queryItems["tlsverifycert"].flatMap { $0.value.flatMap { .init($0) } }) {
            settings.tlsVerifyCert = tlsVerifyCert
        }
        
        if let tlsCaFilePath: String = queryItems["tlscafile"].flatMap({ $0.value }) {
            if let cerificate = parseCertificate(path: tlsCaFilePath) {
                settings.cerificates.append(cerificate)
            }
        }

        if let defaultDeadline: Int = (queryItems["defaultdeadline"].flatMap { $0.value.flatMap { .init($0) }}) {
            settings.defaultDeadline = defaultDeadline
        }
        
        return settings
    }
}

extension ClientSettings {
    public static func parseCertificate(path: String) ->TLSConfig.CertificateSource?{
        
        do{
            let tlsCaFileUrl = URL(fileURLWithPath: path)
            let tlsCaFileData = try Data(contentsOf: tlsCaFileUrl)
            guard !tlsCaFileData.isEmpty else {
                logger.warning("tls ca file is empty.")
                return nil
            }
            
            let format:TLSConfig.SerializationFormat = if let tlsCaContent = String(data: tlsCaFileData, encoding: .ascii),
               tlsCaContent.hasPrefix("-----BEGIN CERTIFICATE-----") {
                .pem
            }else{
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


extension ClientSettings: Buildable{
    
    @discardableResult
    public func cerificate(source: TLSConfig.CertificateSource)->Self{
        return withCopy {
            $0.cerificates.append(source)
        }
    }
    
    @discardableResult
    public func cerificate(path: String)->Self{
        return withCopy {
            if let cerificate = Self.parseCertificate(path: path) {
                $0.cerificates.append(cerificate)
            }
        }
    }
    
    @discardableResult
    public func secure(_ secure: Bool)->Self{
        return withCopy {
            $0.secure = secure
        }
    }
    
    @discardableResult
    public func tlsVerifyCert(_ tlsVerifyCert: Bool)->Self{
        return withCopy {
            $0.tlsVerifyCert = tlsVerifyCert
        }
    }
    
    @discardableResult
    public func defaultDeadline(_ defaultDeadline: Int)->Self{
        return withCopy {
            $0.defaultDeadline = defaultDeadline
        }
    }
    
    @discardableResult
    public func connectionName(_ connectionName: String)->Self{
        return withCopy {
            $0.connectionName = connectionName
        }
    }
    
    @discardableResult
    public func keepAlive(_ keepAlive: KeepAlive)->Self{
        return withCopy {
            $0.keepAlive = keepAlive
        }
    }
    
    @discardableResult
    public func authenticated(_ authenication: Authentication)->Self{
        return withCopy {
            $0.authentication = authenication
        }
    }
    
    @discardableResult
    public func discoveryInterval(_ discoveryInterval: Duration)->Self{
        return withCopy {
            $0.discoveryInterval = discoveryInterval
        }
    }

    @discardableResult
    public func maxDiscoveryAttempts(_ maxDiscoveryAttempts: UInt16)->Self{
        return withCopy {
            $0.maxDiscoveryAttempts = maxDiscoveryAttempts
        }
    }
}


extension ClientSettings {
    internal func makeClient(endpoint: Endpoint) throws(KurrentError) ->GRPCClient<HTTP2ClientTransport.Posix>{
        try withRethrowingError(usage: #function) {
            let transport: HTTP2ClientTransport.Posix = try .http2NIOPosix(
                                                            target: endpoint.target,
                                                            transportSecurity: transportSecurity)
            return GRPCClient<HTTP2ClientTransport.Posix>(transport: transport)
        }
    }
    
    internal var transportSecurity: HTTP2ClientTransport.Posix.TransportSecurity {
        get {
            return if secure {
                .tls { config in
                    if let trustRoots = trustRoots {
                        config.trustRoots = trustRoots
                    }
                }
            } else {
                .plaintext
            }
        }
    }
}
