//
//  Projections.Result.swift
//
//
//  Created by Grady Zhuo on 2023/11/27.
//

import Foundation
import GRPCSupport
import SwiftProtobuf

extension ProjectionsClient {
    public struct Result: UnaryUnary {
        public typealias Request = GenericGRPCRequest<EventStore_Client_Projections_ResultReq>

        public let name: String
        public let options: Options

        init(name: String, options: Options) {
            self.name = name
            self.options = options
        }

        public func build() throws -> Request.UnderlyingMessage {
            .with {
                $0.options = options.build()
                $0.options.name = name
            }
        }
    }
}

extension ProjectionsClient.Result {
    public struct Response: GRPCJSONDecodableResponse {
        public typealias UnderlyingMessage = EventStore_Client_Projections_ResultResp

        public private(set) var jsonValue: Google_Protobuf_Value

        public init(from message: UnderlyingMessage) throws {
            jsonValue = message.result
        }
    }

    public final class Options: EventStoreOptions {
        public typealias UnderlyingMessage = Request.UnderlyingMessage.Options

        var options: UnderlyingMessage

        public init() {
            options = .init()
        }

        public func partition(_ partition: String) -> Self {
            options.partition = partition
            return self
        }

        public func build() -> UnderlyingMessage {
            options
        }
    }
}
