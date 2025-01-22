//
//  Operations.ResignNode.swift
//
//
//  Created by Grady Zhuo on 2023/12/12.
//

import GRPCCore
import GRPCEncapsulates

public struct ResignNode: UnaryUnary {
    public typealias Client = Service
    public typealias UnderlyingRequest = UnderlyingService.Method.ResignNode.Input
    public typealias UnderlyingResponse = UnderlyingService.Method.ResignNode.Output
    public typealias Response = DiscardedResponse<UnderlyingResponse>
    
    public init(){}
    
    public func send(client: Client.UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
        return try await client.resignNode(request: request, options: callOptions){
            try handle(response: $0)
        }
    }
}
