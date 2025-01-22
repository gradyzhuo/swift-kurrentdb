//
//  Operations.Shutdown.swift
//
//
//  Created by Grady Zhuo on 2023/12/12.
//

import GRPCCore
import GRPCEncapsulates

public struct Shutdown: UnaryUnary {
    public typealias Client = Service
    public typealias UnderlyingRequest = UnderlyingService.Method.Shutdown.Input
    public typealias UnderlyingResponse = UnderlyingService.Method.Shutdown.Output
    public typealias Response = DiscardedResponse<UnderlyingResponse>
    
    public init(){}
    
    public func send(client: Client.UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
        return try await client.shutdown(request: request, options: callOptions){
            try handle(response: $0)
        }
    }
}
