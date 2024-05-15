//
//  Projections.Enable.swift
//
//
//  Created by Grady Zhuo on 2023/11/27.
//

import Foundation
import GRPCEncapsulates

extension ProjectionsClient {
    public struct Enable: UnaryUnary {
        public typealias Request = GenericGRPCRequest<EventStore_Client_Projections_EnableReq>
        public typealias Response = DiscardedResponse<EventStore_Client_Projections_EnableResp>

        public let name: String
        public let options: Options

        public func build() throws -> Request.UnderlyingMessage {
            .with {
                $0.options = options.build()
                $0.options.name = name
            }
        }
    }
}

extension ProjectionsClient.Enable {
    public final class Options: EventStoreOptions {
        public typealias UnderlyingMessage = EventStore_Client_Projections_EnableReq.Options

        var options: UnderlyingMessage

        public init() {
            options = .init()
        }

        public func build() -> UnderlyingMessage {
            options
        }
    }
}
