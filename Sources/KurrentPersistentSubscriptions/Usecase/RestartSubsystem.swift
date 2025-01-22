//
//  PersistentSubscriptionsClient.RestartSubsystem.swift
//
//
//  Created by Grady Zhuo on 2023/12/11.
//

import GRPCCore
import GRPCEncapsulates

public struct RestartSubsystem: UnaryUnary {
    public typealias Client = Service
    public typealias UnderlyingRequest = UnderlyingService.Method.RestartSubsystem.Input
    public typealias UnderlyingResponse = UnderlyingService.Method.RestartSubsystem.Output
    public typealias Response = DiscardedResponse<UnderlyingResponse>

    package func requestMessage() throws -> UnderlyingRequest {
        return .init()
    }
    
    public func send(client: Client.UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
        return try await client.restartSubsystem(request: request, options: callOptions){
            try handle(response: $0)
        }
    }
}
