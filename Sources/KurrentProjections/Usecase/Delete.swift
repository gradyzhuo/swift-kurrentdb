//
//  Delete.swift
//  KurrentProjections
//
//  Created by Grady Zhuo on 2023/11/26.
//

import Foundation
import GRPCCore
import GRPCEncapsulates

extension Projections {
    public struct Delete: UnaryUnary {
        package typealias ServiceClient = Client
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.Delete.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.Delete.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        public let name: String
        public let options: Options

        package func requestMessage() throws -> UnderlyingRequest {
            .with {
                $0.options.name = name
                $0.options = options.build()
            }
        }

        package func send(client: ServiceClient, request: GRPCCore.ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            try await client.delete(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}

extension Projections.Delete {
    public struct Options: EventStoreOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        public private(set) var deleteCheckpointStream: Bool
        public private(set) var deleteEmittedStreams: Bool
        public private(set) var deleteStateStream: Bool

        public init(deleteCheckpointStream: Bool = false, deleteEmittedStreams: Bool = false, deleteStateStream: Bool = false) {
            self.deleteCheckpointStream = deleteCheckpointStream
            self.deleteEmittedStreams = deleteEmittedStreams
            self.deleteStateStream = deleteStateStream
        }

        package func build() -> UnderlyingMessage {
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
