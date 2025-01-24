//
//  ProjectionsClient.Disable.swift
//
//
//  Created by Grady Zhuo on 2023/11/27.
//

import Foundation
import GRPCCore
import GRPCEncapsulates

extension Projections {
    public struct Disable: UnaryUnary {
        public typealias ServiceClient = Client
        public typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.Disable.Input
        public typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.Disable.Output
        public typealias Response = DiscardedResponse<UnderlyingResponse>

        public let name: String
        public let options: Options
        
        package func requestMessage() throws -> UnderlyingRequest {
            return .with {
                $0.options = options.build()
                $0.options.name = name
            }
        }
        
        public func send(client: ServiceClient, request: GRPCCore.ClientRequest<UnderlyingRequest>, callOptions: GRPCCore.CallOptions) async throws -> Response {
            return try await client.disable(request: request, options: callOptions){
                try handle(response: $0)
            }
        }
    }
}

extension Projections.Disable {
    public struct Options: EventStoreOptions {
        public typealias UnderlyingMessage = UnderlyingRequest.Options

        var writeCheckpoint: Bool
        
        public init(writeCheckpoint: Bool = false) {
            self.writeCheckpoint = writeCheckpoint
        }

        public func build() -> UnderlyingMessage {
            return .with {
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
