//
//  GRPCClient+Additions.swift
//
//
//  Created by Grady Zhuo on 2023/12/19.
//

import Foundation
import GRPC
import GRPCSupport

public protocol EventStoreGRPCClient: GRPCClient {
    associatedtype InterceptorsFactoryProtocol
    
    init(channel: GRPCChannel, defaultCallOptions: CallOptions, interceptors: InterceptorsFactoryProtocol?
    )
}

extension EventStoreGRPCClient{
    public init(channel: GRPCChannel, defaultCallOptions: CallOptions){
        self.init(channel: channel, defaultCallOptions: defaultCallOptions, interceptors: nil)
    }
}


extension EventStore_Client_Streams_StreamsAsyncClient: EventStoreGRPCClient {
    public typealias InterceptorsFactoryProtocol = EventStore_Client_Streams_StreamsClientInterceptorFactoryProtocol
}

extension EventStore_Client_Users_UsersAsyncClient: EventStoreGRPCClient {
    public typealias InterceptorsFactoryProtocol = EventStore_Client_Users_UsersClientInterceptorFactoryProtocol
}

extension EventStore_Client_Projections_ProjectionsAsyncClient: EventStoreGRPCClient {
    public typealias InterceptorsFactoryProtocol = EventStore_Client_Projections_ProjectionsClientInterceptorFactoryProtocol
}


extension EventStore_Client_PersistentSubscriptions_PersistentSubscriptionsAsyncClient: EventStoreGRPCClient {
    public typealias InterceptorsFactoryProtocol = EventStore_Client_PersistentSubscriptions_PersistentSubscriptionsClientInterceptorFactoryProtocol
}

extension EventStore_Client_Operations_OperationsAsyncClient: EventStoreGRPCClient {
    public typealias InterceptorsFactoryProtocol = EventStore_Client_Operations_OperationsClientInterceptorFactoryProtocol
}

extension EventStore_Client_Monitoring_MonitoringAsyncClient: EventStoreGRPCClient {
    public typealias InterceptorsFactoryProtocol = EventStore_Client_Monitoring_MonitoringClientInterceptorFactoryProtocol
}

extension EventStore_Client_Gossip_GossipAsyncClient: EventStoreGRPCClient {
    public typealias InterceptorsFactoryProtocol = EventStore_Client_Gossip_GossipClientInterceptorFactoryProtocol
}
