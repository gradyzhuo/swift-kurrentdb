//
//  Enable.swift
//  KurrentUsers
//
//  Created by 卓俊諺 on 2025/1/16.
//
import Foundation
import GRPCCore
import GRPCEncapsulates

extension Users {
    public struct Enable: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.Enable.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.Enable.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        package var methodDescriptor: GRPCCore.MethodDescriptor{
            get{
                ServiceClient.UnderlyingService.Method.Enable.descriptor
            }
        }

        package static var name: String{
            get{
                "Users.\(Self.self)"
            }
        }
        
        public let loginName: String

        public init(loginName: String) {
            self.loginName = loginName
        }

        package func requestMessage() throws -> UnderlyingRequest {
            .with {
                $0.options.loginName = loginName
            }
        }

        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            let client = ServiceClient(wrapping: connection)
            return try await client.enable(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}
