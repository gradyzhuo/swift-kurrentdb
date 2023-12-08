//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/10/17.
//

import Foundation
import GRPC
import NIOCore
import NIOPosix
import RegexBuilder
//import ServiceContextModule
import Logging


let logger = Logger(label: "ClientSettings")

public let DEFAULT_PORT_NUMBER = 2113
public let DEFAULT_GOSSIP_TIMEOUT: TimeInterval = 3.0

public struct ClientSettings {
    // public internal(set) var target: ConnectionTarget
    public private(set) var clusterMode: TopologyClusterMode
    public private(set) var transportSecurity: GRPCChannelPool.Configuration.TransportSecurity
    public private(set) var numberOfThreads: Int = 1

    public private(set) var tls: Bool = true
    public private(set) var tlsVerifyCert: Bool = true
    public private(set) var defaultDeadline: Int = .max
    public private(set) var connectionName: String?

    public var keepAlive: KeepAlive = .default
    public var defaultUserCredentials: UserCredentials?

    public init(clusterMode: TopologyClusterMode,
         transportSecurity: GRPCChannelPool.Configuration.TransportSecurity = .plaintext,
         numberOfThreads: Int = 1) {
        self.clusterMode = clusterMode
        self.transportSecurity = transportSecurity
        self.numberOfThreads = numberOfThreads
    }

}

extension GRPCChannelPool{
    public static func with(settings: ClientSettings) throws -> GRPCChannel {
        
        let group = MultiThreadedEventLoopGroup(numberOfThreads: settings.numberOfThreads)

        return switch settings.clusterMode {
            case .singleNode(let endpoint):
             try Self.with(
                target: endpoint.connectionTarget(),
                transportSecurity: settings.transportSecurity,
                eventLoopGroup: group
            )
        case let .dnsDiscovery(endpoint, _, _):
                try Self.with(
                target: endpoint.connectionTarget(),
                transportSecurity: settings.transportSecurity,
                eventLoopGroup: group
            )
        case let .gossipCluster(endpoints, _, _):
                try Self.with(
                target: endpoints.first!.connectionTarget(),
                transportSecurity: settings.transportSecurity,
                eventLoopGroup: group
            )
        }
    }
}


//
extension ClientSettings {
    public static func localhost(port: Int = DEFAULT_PORT_NUMBER, transportSecurity: GRPCChannelPool.Configuration.TransportSecurity = .plaintext) -> Self {
        return .init(clusterMode: .singleNode(at: .init(host: "localhost", port: port)))
    }
    
    @available(macOS 13.0, *)
    public static func parse(connectionString: String) throws -> Self {
        guard let url = URLComponents(string: connectionString) else {
            throw ClientSettingsError.parseError(message: "Unknown connection string: \(connectionString)")
        }
        
        let dnsDiscoverRegex = Regex {
            "esdb"
            ChoiceOf {
                "+discover"
            }
        }
        
        let schemeRegex = Regex{
            "esdb"
            Optionally {
                dnsDiscoverRegex
            }
        }

        guard let scheme = url.scheme, scheme.contains(schemeRegex) else {
            
            throw ClientSettingsError.parseError(message: "Unknown URL scheme: \(String(describing: url.scheme))")
        }

        guard let urlHost = url.host else {
            throw ClientSettingsError.parseError(message: "Connection string doesn't have an host.)")
        }

        let hostsRegex = Regex {
            Optionally(",")
            Capture {
                OneOrMore(
                    .any.subtracting(
                        .anyOf(",:")
                    )
                )
            }
            Optionally{
                ":"
                Capture.init(OneOrMore(.digit)) {
                    Int($0, radix: 10)!
                }
            }
            
        }
        
        let endpoints:[Endpoint] = urlHost.matches(of: hostsRegex)
            .map{
                .init(host: $0.output.1.description, port: $0.output.2)
            }  

        guard endpoints.count > 0 else {
            throw ClientSettingsError.parseError(message: "Connection string doesn't have an host")
        }
       
        let queryItems :[String: URLQueryItem] = .init(uniqueKeysWithValues: url.queryItems.flatMap{
            $0.map{
                ($0.name.lowercased(), $0)
            }
        } ?? [])

        let dnsDiscovery = scheme.contains(dnsDiscoverRegex)
        let clusterMode: TopologyClusterMode 
        if endpoints.count > 1 {
            //gossip mode 
            let nodePreference = queryItems["nodepreference"]?.value.flatMap{
                TopologyClusterMode.NodePreference.init(rawValue:$0)
            } ?? .leader
            let gossipTimeout:TimeInterval = queryItems["gossiptimeout"].flatMap{ $0.value.flatMap{ TimeInterval.init($0)} } ?? DEFAULT_GOSSIP_TIMEOUT
            clusterMode = .gossipCluster(endpoints: endpoints, nodePreference: nodePreference, timeout: gossipTimeout)
        }else{
            let endpoint = endpoints.first!
            if dnsDiscovery {
                // dns discovery mode
                let maxDiscoverAttempts = queryItems["maxdiscoverattempts"].flatMap { $0.value.flatMap{ Int.init($0) } } ?? 3
                let discoverInterval = queryItems["discoveryinterval"].flatMap { $0.value.flatMap{ TimeInterval.init($0) } } ?? 0.5
                clusterMode = .dnsDiscovery(from: endpoint, interval: discoverInterval, maxAttempts: maxDiscoverAttempts)
            }else{
                //singleMode
                clusterMode = .singleNode(at: endpoint)
            }
        }

        var settings = Self.init(clusterMode: clusterMode)

        settings.defaultUserCredentials = if let user = url.user, let password = url.password{
            .init(username: user, password: password)
        }else{
            nil
        }

        if let keepAliveInterval:TimeInterval = (queryItems["keepaliveinterval"].flatMap{ $0.value.flatMap{ .init($0) } }), 
           let keepAliveTimeout:TimeInterval = (queryItems["keepalivetimeout"].flatMap{ $0.value.flatMap{ .init($0) } }) {
            settings.keepAlive = .init(interval: keepAliveInterval, timeout: keepAliveTimeout)
        }

        if let connectionName = queryItems["connectionanme"]?.value {
            settings.connectionName = connectionName
        }

        if let tlsVerifyCert:Bool = (queryItems["tlsverifycert"].flatMap{ $0.value.flatMap{ .init($0) } }){
            settings.tlsVerifyCert = tlsVerifyCert
        }

        if let defaultDeadline:Int = (queryItems["defaultdeadline"].flatMap{ $0.value.flatMap { .init($0) }}){
            settings.defaultDeadline = defaultDeadline
        }        

        return settings
   }
}


extension ClientSettings {

    public enum TopologyClusterMode{
        public enum NodePreference: String {
            case leader = "leader"
            case follower = "follower"
            case random = "random"
            case readOnlyReplica = "readonlyreplica"
        }
        case singleNode(at: Endpoint)
        case dnsDiscovery(from: Endpoint, interval: TimeInterval, maxAttempts: Int)
        case gossipCluster(endpoints: [Endpoint], nodePreference: NodePreference, timeout: TimeInterval)
    }

    public struct Endpoint {
        let host: String
        let port: Int

        init(host: String, port: Int? = nil){
            self.host = host
            self.port = port ?? DEFAULT_PORT_NUMBER
        }

        public func connectionTarget() -> ConnectionTarget {
            return .host(host, port: port)
        }
    }

    public struct UserCredentials {
        let username: String
        let password: String

        var basicAuthHeader: String {
            get throws {
                let credentialString = "\(username):\(password)"
                guard let data = credentialString.data(using: .ascii)else {
                    throw ClientSettingsError.encodingError(message: "\(credentialString) encoding failed.", encoding: .ascii)
                }
                return "Basic: \(data.base64EncodedString())"
            }
        }

        init(username: String, password: String){
            self.username = username
            self.password = password
        }
    }

    public struct KeepAlive{
        public static var `default`: Self = .init(interval: 10.0, timeout: 10.0)

        var interval: TimeInterval
        var timeout: TimeInterval        
    }
}


@available(macOS 13.0, *)
extension ClientSettings : ExpressibleByStringLiteral {
    public typealias StringLiteralType = String
    
    
    public init(stringLiteral value: String) {
        self = try! Self.parse(connectionString: value)
    }
    
    public init(unicodeScalarLiteral value: String) {
        self = try! Self.parse(connectionString: value)
    }
    
    public init(extendedGraphemeClusterLiteral value: String) {
        self = try! Self.parse(connectionString: value)
    }
}
