//
//  ProjectionsClient.Delete.swift
//
//
//  Created by Grady Zhuo on 2023/11/26.
//

import Foundation
import GRPCCore
import GRPCEncapsulates

public struct Delete: UnaryUnary {
    public typealias Client = Projections.Service
    public typealias UnderlyingRequest = UnderlyingService.Method.Delete.Input
    public typealias UnderlyingResponse = UnderlyingService.Method.Delete.Output
    public typealias Response = DiscardedResponse<UnderlyingResponse>

    public let name: String
    public let options: Options
    
    package func requestMessage() throws -> UnderlyingRequest {
        return .with {
            $0.options.name = name
            $0.options = options.build()
        }
    }
    
    public func send(client: Client.UnderlyingClient, request: GRPCCore.ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
        return try await client.delete(request: request, options: callOptions){
            try handle(response: $0)
        }
    }

}

extension Delete {
    public struct Options: EventStoreOptions {
        public typealias UnderlyingMessage = UnderlyingRequest.Options

        public private(set) var deleteCheckpointStream: Bool = false
        public private(set) var deleteEmittedStreams: Bool = false
        public private(set) var deleteStateStream: Bool = false

        public func build() -> UnderlyingMessage {
            return .with { message in
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
