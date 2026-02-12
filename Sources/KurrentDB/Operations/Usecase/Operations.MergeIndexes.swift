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

        package var methodDescriptor: GRPCCore.MethodDescriptor{
            get{
                ServiceClient.UnderlyingService.Method.MergeIndexes.descriptor
            }
        }

        package static var name: String{
            get{
                "Operations.\(Self.self)"
            }
        }
        
        public init() {}

        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            let client = ServiceClient(wrapping: connection)
            return try await client.mergeIndexes(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}
