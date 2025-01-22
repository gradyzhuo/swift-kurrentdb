//
//  ProjectionsClient.Create.swift
//
//
//  Created by Grady Zhuo on 2023/11/22.
//

import Foundation
import GRPCCore
import GRPCEncapsulates

public struct ContinuousCreate: UnaryUnary {
    public typealias Client = Service
    public typealias UnderlyingRequest = UnderlyingService.Method.Create.Input
    public typealias UnderlyingResponse = UnderlyingService.Method.Create.Output
    public typealias Response = DiscardedResponse<UnderlyingResponse>

    public let name: String
    public let query: String
    public let options: Options

    package func requestMessage() throws -> UnderlyingRequest {
        return .with {
            $0.options = options.build()
            $0.options.continuous.name = name
            $0.options.query = query
        }
    }
    
    public func send(client: Client.UnderlyingClient, request: GRPCCore.ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
        return try await client.create(request: request, options: callOptions){
            try handle(response: $0)
        }
    }
    
}

// MARK: - The Options of Continuous Create.

extension ContinuousCreate {
    public struct Options: EventStoreOptions {
        public typealias UnderlyingMessage = UnderlyingRequest.Options

        public private(set) var emitEnabled: Bool
        public private(set) var trackEmittedStreams: Bool

        public init(emitEnabled: Bool = true, trackEmittedStreams: Bool = true) {
            self.emitEnabled = emitEnabled
            self.trackEmittedStreams = trackEmittedStreams
        }
        
        public func build() -> UnderlyingMessage {
            return .with{
                $0.continuous = .with{
                    $0.emitEnabled = emitEnabled
                    $0.trackEmittedStreams = trackEmittedStreams
                }
            }
        }

        @discardableResult
        public func emit(enabled: Bool) -> Self {
            withCopy { options in
                options.emitEnabled = enabled
            }
        }

        @discardableResult
        public func trackEmittedStreams(_ trackEmittedStreams: Bool) -> Self {
            withCopy { options in
                options.trackEmittedStreams = trackEmittedStreams
            }
        }
    }
}
