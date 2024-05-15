//
//  GRPCClient+Additions.swift
//
//
//  Created by Grady Zhuo on 2023/12/19.
//

import Foundation
import GRPC

package protocol UnderlyGRPCClient: GRPCClient {
    associatedtype InterceptorsFactoryProtocol
    
    init(channel: GRPCChannel, defaultCallOptions: CallOptions, interceptors: InterceptorsFactoryProtocol?
    )
}

extension UnderlyGRPCClient{
    public init(channel: GRPCChannel, defaultCallOptions: CallOptions){
        self.init(channel: channel, defaultCallOptions: defaultCallOptions, interceptors: nil)
    }
}


extension EventStore_Client_Streams_StreamsAsyncClient: UnderlyGRPCClient {
    package typealias InterceptorsFactoryProtocol = EventStore_Client_Streams_StreamsClientInterceptorFactoryProtocol
}

extension EventStore_Client_Users_UsersAsyncClient: UnderlyGRPCClient {
    package typealias InterceptorsFactoryProtocol = EventStore_Client_Users_UsersClientInterceptorFactoryProtocol
}

extension EventStore_Client_Projections_ProjectionsAsyncClient: UnderlyGRPCClient {
    package typealias InterceptorsFactoryProtocol = EventStore_Client_Projections_ProjectionsClientInterceptorFactoryProtocol
}


extension EventStore_Client_PersistentSubscriptions_PersistentSubscriptionsAsyncClient: UnderlyGRPCClient {
    package typealias InterceptorsFactoryProtocol = EventStore_Client_PersistentSubscriptions_PersistentSubscriptionsClientInterceptorFactoryProtocol
}

extension EventStore_Client_Operations_OperationsAsyncClient: UnderlyGRPCClient {
    package typealias InterceptorsFactoryProtocol = EventStore_Client_Operations_OperationsClientInterceptorFactoryProtocol
}

extension EventStore_Client_Monitoring_MonitoringAsyncClient: UnderlyGRPCClient {
    package typealias InterceptorsFactoryProtocol = EventStore_Client_Monitoring_MonitoringClientInterceptorFactoryProtocol
}

extension EventStore_Client_Gossip_GossipAsyncClient: UnderlyGRPCClient {
    package typealias InterceptorsFactoryProtocol = EventStore_Client_Gossip_GossipClientInterceptorFactoryProtocol
}
