//
//  Projections.Reset.swift
//
//
//  Created by Grady Zhuo on 2023/12/5.
//

import Foundation
import GRPCSupport

extension ProjectionsClient {
    public struct Reset: UnaryUnary {
        public typealias Request = GenericGRPCRequest<EventStore_Client_Projections_ResetReq>
        public typealias Response = DiscardedResponse<EventStore_Client_Projections_ResetResp>

        let name: String
        let options: Options

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

extension ProjectionsClient.Reset {
    public final class Options: EventStoreOptions {
        public typealias UnderlyingMessage = Request.UnderlyingMessage.Options

        var options: UnderlyingMessage

        public init() {
            options = .with {
                $0.writeCheckpoint = false
            }
        }

        public func writeCheckpoint(enable: Bool) -> Self {
            options.writeCheckpoint = enable
            return self
        }

        public func build() -> ProjectionsClient.Reset.Request.UnderlyingMessage.Options {
            options
        }
    }
}
