//
//  ResignNode.swift
//  KurrentOperations
//
//  Created by Grady Zhuo on 2023/12/12.
//

import GRPCCore
import GRPCEncapsulates

extension Operations {
    public struct ResignNode: UnaryUnary {
        package typealias ServiceClient = Client
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.ResignNode.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.ResignNode.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        public init() {}

        package func send(client: ServiceClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            try await client.resignNode(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}
