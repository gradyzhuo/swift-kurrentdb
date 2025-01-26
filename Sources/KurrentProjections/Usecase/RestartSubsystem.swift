//
//  ProjectionsClient.RestartSubsystem.swift
//
//
//  Created by Grady Zhuo on 2023/12/7.
//

import Foundation
import GRPCCore
import GRPCEncapsulates

extension Projections {
    public struct RestartSubsystem: UnaryUnary {
        package typealias ServiceClient = Client
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.RestartSubsystem.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.RestartSubsystem.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>
        
        package func requestMessage() throws -> UnderlyingRequest {
            return .init()
        }
        
        package func send(client: ServiceClient, request: ClientRequest<UnderlyingRequest>, callOptions: GRPCCore.CallOptions) async throws -> Response {
            return try await client.restartSubsystem(request: request, options: callOptions){
                try handle(response: $0)
            }
        }

    }

}
