//
//  UnderlyGRPCClient.swift
//
//
//  Created by Grady Zhuo on 2023/12/19.
//

import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2

public protocol UnderlyGRPCClient {
    associatedtype Transport: ClientTransport
    init(wrapping: GRPCClient<Transport>)
}

extension EventStore_Client_Streams_Streams.Client: UnderlyGRPCClient {}
extension EventStore_Client_Users_Users.Client: UnderlyGRPCClient {}
extension EventStore_Client_Projections_Projections.Client: UnderlyGRPCClient {}
extension EventStore_Client_PersistentSubscriptions_PersistentSubscriptions.Client: UnderlyGRPCClient{}
extension EventStore_Client_Operations_Operations.Client: UnderlyGRPCClient {}
extension EventStore_Client_Monitoring_Monitoring.Client: UnderlyGRPCClient {}
extension EventStore_Client_Gossip_Gossip.Client: UnderlyGRPCClient {}
