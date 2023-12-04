//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/11/28.
//

import Foundation
import GRPC

@available(macOS 10.15, *)
public struct User {
    
    internal typealias UnderlyingClient = EventStore_Client_Users_UsersAsyncClient
    
    public static var defaultCallOptions: GRPC.CallOptions = .init()
    
    public var callOptions: GRPC.CallOptions{
        get{
            underlyingClient.defaultCallOptions
        }
        set{
            underlyingClient.defaultCallOptions = newValue
        }
    }
    
    internal var channel: GRPCChannel
    internal var underlyingClient: UnderlyingClient
    
    @available(macOS 13.0, *)
    public init(channel: GRPCChannel? = nil) throws{
        self.channel = try channel ??  GRPCChannelPool.with(settings: EventStore.shared.settings)
        self.underlyingClient = .init(channel: self.channel)
        
    }
    
    
    
    
}
