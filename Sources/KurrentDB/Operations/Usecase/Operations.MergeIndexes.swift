//
//  Operations.MergeIndexes.swift
//  KurrentOperations
//
//  Created by Grady Zhuo on 2023/12/12.
//

import GRPCCore
import GRPCEncapsulates

extension Operations {
    public struct MergeIndexes: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.MergeIndexes.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.MergeIndexes.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        public init() {}

        package func send(client: ServiceClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            try await client.mergeIndexes(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}
