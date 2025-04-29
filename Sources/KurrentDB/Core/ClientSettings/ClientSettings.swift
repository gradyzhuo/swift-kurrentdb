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
public let DEFAULT_GOSSIP_TIMEOUT: TimeAmount = .seconds(3)

/// `ClientSettings` encapsulates various configuration settings for a client.
///
/// - Properties:
///   - `configuration`: TLS configuration.
///   - `clusterMode`: The cluster topology mode.
///   - `tls`: Indicates if TLS is enabled (default is false).
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
    public private(set) var clusterMode: TopologyClusterMode

    public var cerificates: [TLSConfig.CertificateSource]
    public var trustRoots: TLSConfig.TrustRootsSource?{
        get{
            guard tls else {
                return nil
            }
            return if cerificates.isEmpty {
                .systemDefault
            }else{
                .certificates(cerificates)
            }
        }
    }

    public private(set) var tls: Bool = false
    public private(set) var tlsVerifyCert: Bool = false
    
    public private(set) var defaultDeadline: Int = .max
    public private(set) var connectionName: String?

    public var keepAlive: KeepAlive = .default
    public var authentication: Authentication?
    public var discoveryInterval: TimeAmount = .microseconds(100)
    public var maxDiscoveryAttempts: UInt16 = 10
    
    
    public init(clusterMode: TopologyClusterMode) {
        self.clusterMode = clusterMode
        self.cerificates = []
    }
}

extension ClientSettings {
    public static func localhost(port: UInt32 = DEFAULT_PORT_NUMBER) -> Self {
        return .init(clusterMode: .standalone(at: .init(host: "localhost", port: port)))
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
        
        let clusterMode: TopologyClusterMode
        guard endpoints.count > 0 else {
            throw .internalParsingError(reason: "empty endpoint.")
        }
        
        switch scheme {
        case .esdb:
            clusterMode = .standalone(at: endpoints[0])
        case .dnsDiscover:
            let nodePreference = queryItems["nodepreference"]?.value.flatMap {
                TopologyClusterMode.NodePreference(rawValue: $0)
            } ?? .leader
            let gossipTimeout: TimeAmount = if let timeout = queryItems["gossiptimeout"].flatMap({ $0.value.flatMap { Int64($0) } }) {
                .microseconds(timeout)
            }else{
                DEFAULT_GOSSIP_TIMEOUT
            }
            
            clusterMode = .gossipCluster(seeds: endpoints, nodePreference: nodePreference, timeout: gossipTimeout)
        }

        var settings = Self(clusterMode: clusterMode)
        
        if let maxDiscoverAttempts = queryItems["maxdiscoverattempts"].flatMap({ $0.value.flatMap { UInt16($0) } }) {
            settings.maxDiscoveryAttempts = maxDiscoverAttempts
        }
        
        if let discoverInterval = queryItems["discoveryinterval"].flatMap({ $0.value.flatMap { Int64($0) } }){
            settings.discoveryInterval = .microseconds(discoverInterval)
        }
        
        if let authentication = userCredentialParser.parse(connectionString) {
            settings.authentication = authentication
        }

        if let keepAliveInterval: TimeInterval = (queryItems["keepaliveinterval"].flatMap { $0.value.flatMap { .init($0) } }),
           let keepAliveTimeout: TimeInterval = (queryItems["keepalivetimeout"].flatMap { $0.value.flatMap { .init($0) } })
        {
            settings.keepAlive = .init(interval: keepAliveInterval, timeout: keepAliveTimeout)
        }

        if let connectionName = queryItems["connectionanme"]?.value {
            settings.connectionName = connectionName
        }
        
        if let tls: Bool = (queryItems["tls"].flatMap { $0.value.flatMap { .init($0) } }) {
            settings.tls = tls
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
    public func clusterMode(_ clusterMode: TopologyClusterMode)->Self{
        return withCopy {
            $0.clusterMode = clusterMode
        }
    }
    
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
    public func tls(_ tls: Bool)->Self{
        return withCopy {
            $0.tls = tls
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
    public func discoveryInterval(_ discoveryInterval: TimeAmount)->Self{
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
    internal var transportSecurity: HTTP2ClientTransport.Posix.TransportSecurity {
        get {
            return if tls {
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
