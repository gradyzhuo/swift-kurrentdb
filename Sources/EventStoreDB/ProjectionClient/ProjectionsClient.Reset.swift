//
//  ProjectionsClient.Reset.swift
//
//
//  Created by Grady Zhuo on 2023/12/5.
//

import Foundation
import GRPCEncapsulates

extension ProjectionsClient {
    public struct Reset: UnaryUnary {
        public typealias Request = GenericGRPCRequest<EventStore_Client_Projections_ResetReq>
        public typealias Response = DiscardedResponse<EventStore_Client_Projections_ResetResp>

        let name: String
        let options: Options

        package func build() throws -> Request.UnderlyingMessage {
            .with {
                $0.options = options.build()
                $0.options.name = name
            }
        }
    }
}

extension ProjectionsClient.Reset {
    public struct Options: EventStoreOptions {
        public typealias UnderlyingMessage = Request.UnderlyingMessage.Options

        var writeCheckpoint: Bool = false

        public func writeCheckpoint(enable: Bool) -> Self {
            withCopy { options in
                options.writeCheckpoint = enable
            }
        }

        package func build() -> ProjectionsClient.Reset.Request.UnderlyingMessage.Options {
            .with {
                $0.writeCheckpoint = writeCheckpoint
            }
        }
    }
}
