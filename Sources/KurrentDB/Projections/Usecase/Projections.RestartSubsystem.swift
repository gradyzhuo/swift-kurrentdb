//
//  Projections.RestartSubsystem.swift
//  KurrentProjections
//
//  Created by Grady Zhuo on 2023/12/7.
//

import Foundation
import GRPCCore
import GRPCEncapsulates

extension Projections {
    public struct RestartSubsystem: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.RestartSubsystem.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.RestartSubsystem.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        package func requestMessage() throws -> UnderlyingRequest {
            .init()
        }

        package func send(client: ServiceClient, request: ClientRequest<UnderlyingRequest>, callOptions: GRPCCore.CallOptions) async throws -> Response {
            try await client.restartSubsystem(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}
