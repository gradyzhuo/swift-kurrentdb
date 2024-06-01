//
//  ProjectionsClient.Delete.swift
//
//
//  Created by Grady Zhuo on 2023/11/26.
//

import Foundation
import GRPCEncapsulates

extension ProjectionsClient {
    public struct Delete: UnaryUnary {
        public typealias Request = GenericGRPCRequest<EventStore_Client_Projections_DeleteReq>
        public typealias Response = DiscardedResponse<EventStore_Client_Projections_DeleteResp>

        public let name: String
        public let options: Options

        package func build() throws -> Request.UnderlyingMessage {
            .with {
                $0.options.name = name
                $0.options = options.build()
            }
        }
    }
}

extension ProjectionsClient.Delete {
    public struct Options: EventStoreOptions {
        public typealias UnderlyingMessage = EventStore_Client_Projections_DeleteReq.Options

        public private(set) var deleteCheckpointStream: Bool = false
        public private(set) var deleteEmittedStreams: Bool = false
        public private(set) var deleteStateStream: Bool = false

        public func build() -> UnderlyingMessage {
            .with { message in
                message.deleteStateStream = deleteStateStream
                message.deleteEmittedStreams = deleteEmittedStreams
                message.deleteCheckpointStream = deleteCheckpointStream
            }
        }

        @discardableResult
        public func deleteEmittedStreams(enabled: Bool) -> Self {
            withCopy { options in
                options.deleteEmittedStreams = enabled
            }
        }

        @discardableResult
        public func deleteStateStream(enabled: Bool) -> Self {
            withCopy { options in
                options.deleteStateStream = enabled
            }
        }

        @discardableResult
        public func deleteCheckpointStream(enabled: Bool) -> Self {
            withCopy { options in
                options.deleteCheckpointStream = enabled
            }
        }
    }
}
