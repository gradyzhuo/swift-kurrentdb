//
//  GRPCChannelPool+Additionals.swift
//
//
//  Created by Grady Zhuo on 2024/5/25.
//

import Foundation
import GRPC
import NIOCore
import NIOPosix
import NIOSSL

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
