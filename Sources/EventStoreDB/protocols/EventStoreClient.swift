//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/12/7.
//

import Foundation
import SwiftProtobuf
import GRPC

public protocol EventStoreClient {
    associatedtype UnderlyingClient: GRPCClient
    
    var clientSettings: ClientSettings { set get }
    var channel: GRPCChannel { get }
    
    func makeClient(callOptions: CallOptions) throws -> UnderlyingClient
}


extension EventStoreClient {
    
    public var underlyingClient: UnderlyingClient{
        get throws{
            let options = try clientSettings.makeCallOptions()
            return try makeClient(callOptions: options)
        }
    }
    
}

