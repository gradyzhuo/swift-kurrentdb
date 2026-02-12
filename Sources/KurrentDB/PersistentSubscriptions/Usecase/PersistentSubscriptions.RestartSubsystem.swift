//
//  PersistentSubscriptions.RestartSubsystem.swift
//  KurrentPersistentSubscriptions
//
//  Created by Grady Zhuo on 2023/12/11.
//

import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions {
    public struct RestartSubsystem: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = UnderlyingService.Method.RestartSubsystem.Input
        package typealias UnderlyingResponse = UnderlyingService.Method.RestartSubsystem.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        package var methodDescriptor: GRPCCore.MethodDescriptor{
            get{
                ServiceClient.UnderlyingService.Method.RestartSubsystem.descriptor
            }
        }

        package static var name: String{
            get{
                "PersistentSubscriptions.\(Self.self)"
            }
        }
        
        package func requestMessage() throws -> UnderlyingRequest {
            .init()
        }

        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            let client = ServiceClient(wrapping: connection)
            return try await client.restartSubsystem(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}
