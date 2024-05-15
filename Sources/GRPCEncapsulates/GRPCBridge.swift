//
//  GRPCBridge.swift
//
//
//  Created by Grady Zhuo on 2023/10/29.
//

import Foundation
import GRPC
import SwiftProtobuf

public protocol GRPCBridge {
    associatedtype UnderlyingMessage: SwiftProtobuf.Message
}

public protocol GRPCRequest: GRPCBridge {}

public protocol GRPCResponse: GRPCBridge {
    init(from message: UnderlyingMessage) throws
}

public struct GenericGRPCRequest<Message: SwiftProtobuf.Message>: GRPCRequest {
    public typealias UnderlyingMessage = Message
}

public struct DiscardedResponse<R: Message>: GRPCResponse {
    public typealias UnderlyingMessage = R

    public init(from _: UnderlyingMessage) throws {}
}

public protocol GRPCJSONDecodableResponse: GRPCResponse {
    var jsonValue: Google_Protobuf_Value { get }
}

extension GRPCJSONDecodableResponse {
    public func decode<T: Decodable>(to type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        let data = try jsonValue.jsonUTF8Data()
        return try decoder.decode(type, from: data)
    }
}
