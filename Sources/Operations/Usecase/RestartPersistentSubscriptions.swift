//
//  Operations.RestartPersistentSubscriptions.swift
//
//
//  Created by Grady Zhuo on 2023/12/12.
//

import GRPCCore
import GRPCEncapsulates

public struct RestartPersistentSubscriptions: UnaryUnary {
    public typealias Client = Operations.Service
    public typealias UnderlyingRequest = UnderlyingService.Method.RestartPersistentSubscriptions.Input
    public typealias UnderlyingResponse = UnderlyingService.Method.RestartPersistentSubscriptions.Output
    public typealias Response = DiscardedResponse<UnderlyingResponse>
    
    public init(){}
    
    public func send(client: Client.UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
        return try await client.restartPersistentSubscriptions(request: request, options: callOptions){
            try handle(response: $0)
        }
    }
    
    
}
