//
//  Shutdown.swift
//  KurrentOperations
//
//  Created by Grady Zhuo on 2023/12/12.
//

import GRPCCore
import GRPCEncapsulates

extension Operations {
    public struct Shutdown: UnaryUnary {
        package typealias ServiceClient = Client
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.Shutdown.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.Shutdown.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        public init() {}

        package func send(client: ServiceClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            try await client.shutdown(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}
