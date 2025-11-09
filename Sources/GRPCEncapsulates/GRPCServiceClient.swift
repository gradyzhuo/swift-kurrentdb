//
//  GRPCServiceClient.swift
//  GRPCEncapsulates
//
//  Created by Grady Zhuo on 2023/12/19.
//

import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import Generated

public protocol GRPCServiceClient {
    associatedtype UnderlyingService
    associatedtype Transport: ClientTransport
    init(wrapping: GRPCClient<Transport>)
}

extension EventStore_Client_Streams_Streams.Client: GRPCServiceClient {
    package typealias UnderlyingService = EventStore_Client_Streams_Streams
}

extension EventStore_Client_Users_Users.Client: GRPCServiceClient {
    package typealias UnderlyingService = EventStore_Client_Users_Users
}

extension EventStore_Client_Projections_Projections.Client: GRPCServiceClient {
    package typealias UnderlyingService = EventStore_Client_Projections_Projections
}

extension EventStore_Client_PersistentSubscriptions_PersistentSubscriptions.Client: GRPCServiceClient {
    package typealias UnderlyingService = EventStore_Client_PersistentSubscriptions_PersistentSubscriptions
}

extension EventStore_Client_Operations_Operations.Client: GRPCServiceClient {
    package typealias UnderlyingService = EventStore_Client_Operations_Operations
}

extension EventStore_Client_Monitoring_Monitoring.Client: GRPCServiceClient {
    package typealias UnderlyingService = EventStore_Client_Monitoring_Monitoring
}

extension EventStore_Client_Gossip_Gossip.Client: GRPCServiceClient {
    package typealias UnderlyingService = EventStore_Client_Gossip_Gossip
}

extension EventStore_Client_ServerFeatures_ServerFeatures.Client: GRPCServiceClient {
    package typealias UnderlyingService = EventStore_Client_ServerFeatures_ServerFeatures
}
