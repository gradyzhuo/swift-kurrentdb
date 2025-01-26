//
//  PersistentSubscriptionsClient.RestartSubsystem.swift
//
//
//  Created by Grady Zhuo on 2023/12/11.
//

import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions {
    public struct RestartSubsystem: UnaryUnary {
        package typealias ServiceClient = Client
        package typealias UnderlyingRequest = UnderlyingService.Method.RestartSubsystem.Input
        package typealias UnderlyingResponse = UnderlyingService.Method.RestartSubsystem.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        package func requestMessage() throws -> UnderlyingRequest {
            return .init()
        }
        
        package func send(client: Client, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            return try await client.restartSubsystem(request: request, options: callOptions){
                try handle(response: $0)
            }
        }
    }
}
