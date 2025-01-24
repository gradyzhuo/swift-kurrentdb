//
//  Operations.SetNodePriority.swift
//
//
//  Created by Grady Zhuo on 2023/12/12.
//

import GRPCCore
import GRPCEncapsulates

extension Operations {
    public struct SetNodePriority: UnaryUnary {
        public typealias ServiceClient = Client
        public typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.SetNodePriority.Input
        public typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.SetNodePriority.Output
        public typealias Response = DiscardedResponse<UnderlyingResponse>

        public let priority: Int32
        
        public init(priority: Int32) {
            self.priority = priority
        }

        package func requestMessage() throws -> UnderlyingRequest {
            return .with {
                $0.priority = priority
            }
        }
        
        public func send(client: ServiceClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            return try await client.setNodePriority(request: request, options: callOptions){
                try handle(response: $0)
            }
        }
    }
}
