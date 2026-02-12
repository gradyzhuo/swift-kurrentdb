//
//  Operations.ResignNode.swift
//  KurrentOperations
//
//  Created by Grady Zhuo on 2023/12/12.
//

import GRPCCore
import GRPCEncapsulates

extension Operations {
    public struct ResignNode: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.ResignNode.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.ResignNode.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        package var methodDescriptor: GRPCCore.MethodDescriptor{
            get{
                ServiceClient.UnderlyingService.Method.ResignNode.descriptor
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
            return try await client.resignNode(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}
