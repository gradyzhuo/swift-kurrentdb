//
//  Projections.Create.swift
//
//
//  Created by Grady Zhuo on 2023/11/22.
//

import Foundation
import GRPCEncapsulates
import SwiftProtobuf

extension ProjectionsClient {
    public struct ContinuousCreate: UnaryUnary {
        public typealias Request = GenericGRPCRequest<EventStore_Client_Projections_CreateReq>
        public typealias Response = DiscardedResponse<EventStore_Client_Projections_CreateResp>

        public let name: String
        public let query: String
        public let options: Options

        public func build() throws -> Request.UnderlyingMessage {
            .with {
                $0.options = options.build()
                $0.options.continuous.name = name
                $0.options.query = query
            }
        }
    }
}

// MARK: - The Options of Continuous Create.

extension ProjectionsClient.ContinuousCreate {
    public final class Options: EventStoreOptions {
        public typealias UnderlyingMessage = EventStore_Client_Projections_CreateReq.Options

        var options: UnderlyingMessage

        public var emitEnabled: Bool {
            didSet {
                options.continuous.emitEnabled = emitEnabled
            }
        }

        public func build() -> UnderlyingMessage {
            options
        }

        public var trackEmittedStreams: Bool {
            didSet {
                options.continuous.trackEmittedStreams = trackEmittedStreams
            }
        }

        public init() {
            options = .with {
                $0.continuous = .init()
            }
            emitEnabled = true
            trackEmittedStreams = true
        }

        @discardableResult
        public func emit(enabled: Bool) -> Self {
            emitEnabled = enabled
            return self
        }

        @discardableResult
        public func trackEmittedStreams(_ trackEmittedStreams: Bool) -> Self {
            self.trackEmittedStreams = trackEmittedStreams
            return self
        }
    }
}
