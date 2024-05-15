//
//  Projections.Delete.swift
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

        public func build() throws -> Request.UnderlyingMessage {
            .with {
                $0.options.name = name
                $0.options = options.build()
            }
        }
    }
}

extension ProjectionsClient.Delete {
    public class Options: EventStoreOptions {
        public typealias UnderlyingMessage = EventStore_Client_Projections_DeleteReq.Options

        public var options: UnderlyingMessage

        public init() {
            options = .init()
            deleteCheckpointStream(enabled: false)
            deleteEmittedStreams(enabled: false)
            deleteStateStream(enabled: false)
        }

        public func build() -> UnderlyingMessage {
            options
        }

        @discardableResult
        public func deleteEmittedStreams(enabled: Bool) -> Self {
            options.deleteEmittedStreams = enabled
            return self
        }

        @discardableResult
        public func deleteStateStream(enabled: Bool) -> Self {
            options.deleteStateStream = enabled
            return self
        }

        @discardableResult
        public func deleteCheckpointStream(enabled: Bool) -> Self {
            options.deleteCheckpointStream = enabled
            return self
        }
    }
}
