//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/10/29.
//

import Foundation
import GRPC
import SwiftProtobuf

public protocol GRPCBridge {
    associatedtype UnderlyingMessage: SwiftProtobuf.Message
    
}

// delete

public protocol GRPCRequest: GRPCBridge { }
public protocol GRPCResponse: GRPCBridge { }


protocol StreamRequest: GRPCRequest {
    func build() throws -> [UnderlyingMessage]
}
protocol UnaryRequest: GRPCRequest{
    func build() throws -> UnderlyingMessage
}

protocol UnaryResponse: GRPCResponse{
    init(from message: UnderlyingMessage)
}

//protocol StreamResponse: GRPCResponse {
//    init(from messages: [UnderlyingMessage])
//    
//}
