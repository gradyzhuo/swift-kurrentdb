//
//  Operations.Shutdown.swift
//  KurrentOperations
//
//  Created by Grady Zhuo on 2023/12/12.
//

import GRPCCore
import GRPCEncapsulates

extension Operations {
    public struct Shutdown: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.Shutdown.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.Shutdown.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        package var methodDescriptor: GRPCCore.MethodDescriptor {
            ServiceClient.UnderlyingService.Method.Shutdown.descriptor
        }

        package static var name: String {
            "Operations.\(Self.self)"
        }

        public init() {}

        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            let client = ServiceClient(wrapping: connection)
            return try await client.shutdown(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}
