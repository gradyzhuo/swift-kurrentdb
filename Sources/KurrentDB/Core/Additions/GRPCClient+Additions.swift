//
//  GRPCClient+Additions.swift
//  KurrentCore
//
//  Created by Grady Zhuo on 2024/5/25.
//

import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import NIOCore
import NIOTransportServices

extension GRPCClient where Transport == HTTP2ClientTransport.Posix {
    package convenience init(settings: ClientSettings, interceptors: [any ClientInterceptor] = [], eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup) throws(KurrentError) {
        let transportSecurity = if settings.tls {
            Transport.TransportSecurity.tls { config in
                if let trustRoots = settings.trustRoots {
                    config.trustRoots = trustRoots
                }
            }

        } else {
            Transport.TransportSecurity.plaintext
        }

        do{
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
        }catch let error as RuntimeError{
            throw KurrentError.grpcRuntimeError(cause: error)
        }catch {
            throw .initializationError(reason: "GRPCClient initialize failed: \(error)")
        }
    }
}

