//
//  GRPCBridge.swift
//
//
//  Created by Grady Zhuo on 2023/10/29.
//

import Foundation
import GRPCCore
import SwiftProtobuf

public protocol GRPCBridge: Sendable {
    associatedtype UnderlyingMessage: SwiftProtobuf.Message, Sendable
}

public protocol GRPCRequest: GRPCBridge {}

public protocol GRPCResponse<UnderlyingMessage>: GRPCBridge {
    init(from message: UnderlyingMessage) throws
}

public struct GenericGRPCRequest<M>: GRPCRequest where M: Message, M: Sendable {
    public typealias UnderlyingMessage = M
}

public struct DiscardedResponse<M>: GRPCResponse where M: Message, M: Sendable {
    public typealias UnderlyingMessage = M

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
