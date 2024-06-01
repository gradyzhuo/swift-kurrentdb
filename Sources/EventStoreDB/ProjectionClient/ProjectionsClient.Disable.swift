//
//  ProjectionsClient.Disable.swift
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

        package func build() throws -> Request.UnderlyingMessage {
            .with {
                $0.options = options.build()
                $0.options.name = name
            }
        }
    }
}

extension ProjectionsClient.Disable {
    public struct Options: EventStoreOptions {
        public typealias UnderlyingMessage = EventStore_Client_Projections_DisableReq.Options

        var writeCheckpoint: Bool = false

        public func build() -> UnderlyingMessage {
            .with {
                $0.writeCheckpoint = writeCheckpoint
            }
        }

        @discardableResult
        public func writeCheckpoint(enabled: Bool) -> Self {
            withCopy { options in
                options.writeCheckpoint = enabled
            }
        }
    }
}
