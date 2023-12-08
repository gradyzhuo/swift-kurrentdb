//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/12/7.
//

import Foundation
import SwiftProtobuf
import GRPC

/*
 internal typealias UnderlyingClient = EventStore_Client_Projections_ProjectionsAsyncClient
 
 public private(set) var mode: Mode
 public private(set) var clientSettings: ClientSettings
 public var channel: GRPCChannel{
     get throws{
         try GRPCChannelPool.with(settings: clientSettings)
     }
 }
 
 public static var defaultCallOptions: GRPC.CallOptions = .init()
 
 public var callOptions: GRPC.CallOptions{
     get{
         underlyingClient.defaultCallOptions
     }
     set{
         underlyingClient.defaultCallOptions = newValue
     }
 }
 
 var underlyingClient: UnderlyingClient
 */
internal protocol _GRPCClient {
    associatedtype UnderlyingClient: GRPCClient
    
    var clientSettings: ClientSettings { get }
    var underlyingClient: UnderlyingClient { set get }
}

extension _GRPCClient {
    public var callOptions: GRPC.CallOptions{
        get{
            underlyingClient.defaultCallOptions
        }
        set{
            underlyingClient.defaultCallOptions = newValue
        }
    }
}
