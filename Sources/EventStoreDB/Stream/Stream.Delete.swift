//
//  Stream.Delete.swift
//
//
//  Created by Grady Zhuo on 2023/10/31.
//

import Foundation
import GRPCSupport

extension StreamClient {
    public struct Delete: UnaryUnary {
        public typealias Request = GenericGRPCRequest<EventStore_Client_Streams_DeleteReq>

        public let streamIdentifier: StreamClient.Identifier
        public let options: Options

        public func build() throws -> Request.UnderlyingMessage {
            try .with {
                $0.options = options.build()
                $0.options.streamIdentifier = try streamIdentifier.build()
            }
        }
    }
}

extension StreamClient.Delete {
    public struct Response: GRPCResponse {
        public typealias UnderlyingMessage = EventStore_Client_Streams_DeleteResp

        public internal(set) var position: StreamClient.Position.Option

        public init(from message: UnderlyingMessage) throws {
            let position = message.positionOption?.represented() ?? .noPosition
            self.position = position
        }
    }
}
