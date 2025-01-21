//
//  Operations.MergeIndexes.swift
//
//
//  Created by Grady Zhuo on 2023/12/12.
//

import GRPCCore
import GRPCEncapsulates

public struct MergeIndexes: UnaryUnary {
    public typealias Client = Operations.Service
    public typealias UnderlyingRequest = UnderlyingService.Method.MergeIndexes.Input
    public typealias UnderlyingResponse = UnderlyingService.Method.MergeIndexes.Output
    public typealias Response = DiscardedResponse<UnderlyingResponse>
    
    public init(){}
    
    public func send(client: Client.UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
        return try await client.mergeIndexes(request: request, options: callOptions){
            try handle(response: $0)
        }
    }
}
