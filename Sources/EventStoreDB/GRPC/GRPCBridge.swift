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
    
    
}

// delete

public protocol GRPCRequest: GRPCBridge { 
    associatedtype UnderlyingMessage: SwiftProtobuf.Message
    
}

public protocol GRPCResponse: GRPCBridge {
    associatedtype UnderlyingMessage: SwiftProtobuf.Message
    
    init(from message: UnderlyingMessage) throws
}

//@available(macOS 10.15, *)
//public protocol StreamResponse: AsyncSequence where Self.Element: UnaryResponse{
//    
//}


public struct DiscardedResponse<R: Message>: GRPCResponse{
    public typealias UnderlyingMessage = R
    
    public init(from message: UnderlyingMessage) throws {
        
    }
    
}

public protocol GRPCJSONDecodableResponse: GRPCResponse {
    var jsonValue: Google_Protobuf_Value { get }
    
}

extension GRPCJSONDecodableResponse {
    func decode<T: Decodable>(to type: T.Type) throws ->T {
        let decoder = JSONDecoder()
        let data = try jsonValue.jsonUTF8Data()
        return try decoder.decode(type, from: data)
    }
}



//protocol StreamResponse: GRPCResponse {
//    init(from messages: [UnderlyingMessage])
//    
//}
