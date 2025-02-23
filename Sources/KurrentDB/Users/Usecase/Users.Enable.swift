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

        public let loginName: String

        public init(loginName: String) {
            self.loginName = loginName
        }

        package func requestMessage() throws -> UnderlyingRequest {
            .with {
                $0.options.loginName = loginName
            }
        }

        package func send(client: ServiceClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            try await client.enable(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}
