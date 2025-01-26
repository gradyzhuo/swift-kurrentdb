//
//  GRPCBridge.swift
//
//
//  Created by Grady Zhuo on 2023/10/29.
//

import Foundation
import GRPCCore
import SwiftProtobuf

package protocol GRPCBridge: Sendable {
    associatedtype UnderlyingMessage: SwiftProtobuf.Message, Sendable
}

package protocol GRPCRequest: GRPCBridge {}

package protocol GRPCResponse<UnderlyingMessage>: GRPCBridge {
    init(from message: UnderlyingMessage) throws
}

public struct GenericGRPCRequest<M>: GRPCRequest where M: Message, M: Sendable {
    package typealias UnderlyingMessage = M
}

public struct DiscardedResponse<M>: GRPCResponse where M: Message, M: Sendable {
    package typealias UnderlyingMessage = M

    package init(from message: UnderlyingMessage) throws {}
}

package protocol GRPCJSONDecodableResponse: GRPCResponse {
    var jsonValue: Google_Protobuf_Value { get }
}

extension GRPCJSONDecodableResponse {
    public func decode<T: Decodable>(to type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        let data = try jsonValue.jsonUTF8Data()
        return try decoder.decode(type, from: data)
    }
}
