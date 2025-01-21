//
//  GRPCChannelPool+Additionals.swift
//
//
//  Created by Grady Zhuo on 2024/5/25.
//

import Foundation
import NIOCore
import GRPCCore
import GRPCNIOTransportHTTP2
import NIOTransportServices

extension GRPCClient where Transport == HTTP2ClientTransport.Posix {
    package convenience init(settings: ClientSettings, interceptors: [any ClientInterceptor] = [], eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup) throws{
        let transportSecurity = if settings.tls {
            Transport.TransportSecurity.tls { config in
                if let trustRoots = settings.trustRoots {
                    config.trustRoots = trustRoots
                }
            }
            
        } else {
            Transport.TransportSecurity.plaintext
        }
        
        
        let transport: Transport = switch settings.clusterMode {
        case let .singleNode(endpoint):
                try .http2NIOPosix(
                target: .dns(host: endpoint.host, port: Int(endpoint.port)),
                transportSecurity: transportSecurity,
                eventLoopGroup: eventLoopGroup
            )
        case let .dnsDiscovery(endpoint, _, _):
                try .http2NIOPosix(
                    target: .dns(host: endpoint.host, port: Int(endpoint.port)),
                    transportSecurity: transportSecurity,
                    eventLoopGroup: eventLoopGroup
                )
        case let .gossipCluster(endpoints, _, _):
                try .http2NIOPosix(
                    target: .dns(host: endpoints.first!.host, port: Int(endpoints.first!.port)),
                    transportSecurity: transportSecurity,
                    eventLoopGroup: eventLoopGroup
                )
        }
        self.init(transport: transport, interceptors: interceptors)
    }
}



//public func withGRPCClient<Result: Sendable>(
//  settings: ClientSettings,
//  interceptors: [any ClientInterceptor] = [],
//  isolation: isolated (any Actor)? = #isolation,
//  eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup,
//  handleClient: (GRPCClient<HTTP2ClientTransport.Posix>) async throws -> Result
//) async throws -> Result {
//    let transportSecurity = if settings.tls {
//        HTTP2ClientTransport.Posix.TransportSecurity.tls { config in
//            if let trustRoots = settings.trustRoots {
//                config.trustRoots = trustRoots
//            }
//        }
//    } else {
//        HTTP2ClientTransport.Posix.TransportSecurity.plaintext
//    }
//    
//    
//    let transport: HTTP2ClientTransport.Posix = switch settings.clusterMode {
//    case let .singleNode(endpoint):
//            try .http2NIOPosix(
//            target: .dns(host: endpoint.host, port: Int(endpoint.port)),
//            transportSecurity: transportSecurity,
//            eventLoopGroup: eventLoopGroup
//        )
//    case let .dnsDiscovery(endpoint, _, _):
//            try .http2NIOPosix(
//                target: .dns(host: endpoint.host, port: Int(endpoint.port)),
//                transportSecurity: transportSecurity,
//                eventLoopGroup: eventLoopGroup
//            )
//    case let .gossipCluster(endpoints, _, _):
//            try .http2NIOPosix(
//                target: .dns(host: endpoints.first!.host, port: Int(endpoints.first!.port)),
//                transportSecurity: transportSecurity,
//                eventLoopGroup: eventLoopGroup
//            )
//    }
//    
//    return try await withGRPCClient(
//    transport: transport,
//    interceptors: interceptors,
//    isolation: isolation,
//    handleClient: handleClient
//  )
//}


//package func withEventStoreService<Result: Sendable, UnderlyingClient: GRPCConcreteClient>(
//    of: UnderlyingClient.Type,
//    settings: ClientSettings,
//    metadata: Metadata,
//    callOptions: CallOptions,
//    interceptors: [any ClientInterceptor] = [],
//    isolation: isolated (any Actor)? = #isolation,
//    eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup,
//    handler: (UnderlyingClient) async throws -> Result
//) async throws -> Result {
//    try await withGRPCClient(settings: settings, interceptors: interceptors, isolation: isolation, eventLoopGroup: eventLoopGroup){
//        let underlying = UnderlyingClient(wrapping: $0, metadata: metadata, callOptions: callOptions)
//        return try await handler(underlying)
//    }
//}

