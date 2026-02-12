//
//  Operations.SetNodePriority.swift
//  KurrentOperations
//
//  Created by Grady Zhuo on 2023/12/12.
//

import GRPCCore
import GRPCEncapsulates

extension Operations {
    public struct SetNodePriority: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.SetNodePriority.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.SetNodePriority.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        package var methodDescriptor: GRPCCore.MethodDescriptor{
            get{
                ServiceClient.UnderlyingService.Method.SetNodePriority.descriptor
            }
        }

        package static var name: String{
            get{
                "Operations.\(Self.self)"
            }
        }
        
        public let priority: Int32

        public init(priority: Int32) {
            self.priority = priority
        }

        package func requestMessage() throws -> UnderlyingRequest {
            .with {
                $0.priority = priority
            }
        }

        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            let client = ServiceClient(wrapping: connection)
            return try await client.setNodePriority(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}
