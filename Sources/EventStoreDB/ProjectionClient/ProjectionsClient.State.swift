//
//  ProjectionsClient.State.swift
//
//
//  Created by Grady Zhuo on 2023/11/27.
//

import Foundation
import GRPCEncapsulates
import SwiftProtobuf

extension ProjectionsClient {
    public struct State: UnaryUnary {
        public typealias Request = GenericGRPCRequest<EventStore_Client_Projections_StateReq>

        public let name: String
        public let options: Options

        package func build() throws -> Request.UnderlyingMessage {
            .with {
                $0.options = options.build()
                $0.options.name = name
            }
        }
    }
}

extension ProjectionsClient.State {
    public struct Response: GRPCJSONDecodableResponse {
        public typealias UnderlyingMessage = EventStore_Client_Projections_StateResp

        public private(set) var jsonValue: SwiftProtobuf.Google_Protobuf_Value

        public init(from message: UnderlyingMessage) throws {
            jsonValue = message.state
        }
    }

    public struct Options: EventStoreOptions {
        public typealias UnderlyingMessage = Request.UnderlyingMessage.Options

        var partition: String?

        public func partition(_ partition: String) -> Self {
            withCopy { options in
                options.partition = partition
            }
        }

        package func build() -> UnderlyingMessage {
            .with {
                if let partition {
                    $0.partition = partition
                }
            }
        }
    }
}
