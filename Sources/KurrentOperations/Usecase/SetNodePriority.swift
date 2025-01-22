//
//  Operations.SetNodePriority.swift
//
//
//  Created by Grady Zhuo on 2023/12/12.
//

import GRPCCore
import GRPCEncapsulates

public struct SetNodePriority: UnaryUnary {
    public typealias Client = Service
    public typealias UnderlyingRequest = UnderlyingService.Method.SetNodePriority.Input
    public typealias UnderlyingResponse = UnderlyingService.Method.SetNodePriority.Output
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
    
    public func send(client: Client.UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
        return try await client.setNodePriority(request: request, options: callOptions){
            try handle(response: $0)
        }
    }
}
