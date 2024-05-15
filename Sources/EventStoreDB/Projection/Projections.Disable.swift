//
//  Projections.Disable.swift
//
//
//  Created by Grady Zhuo on 2023/11/27.
//

import Foundation
import GRPCEncapsulates

extension ProjectionsClient {
    public struct Disable: UnaryUnary {
        public typealias Request = GenericGRPCRequest<EventStore_Client_Projections_DisableReq>
        public typealias Response = DiscardedResponse<EventStore_Client_Projections_DisableResp>

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

extension ProjectionsClient.Disable {
    public final class Options: EventStoreOptions {
        public typealias UnderlyingMessage = EventStore_Client_Projections_DisableReq.Options

        var options: UnderlyingMessage

        public init() {
            options = .with {
                $0.writeCheckpoint = false
            }
        }

        public func build() -> UnderlyingMessage {
            options
        }

        @discardableResult
        public func writeCheckpoint(enabled: Bool) -> Self {
            options.writeCheckpoint = enabled
            return self
        }
    }
}
