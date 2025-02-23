//
//  Users.Disable.swift
//  KurrentUsers
//
//  Created by 卓俊諺 on 2025/1/16.
//

import Foundation
import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix

extension Users {
    public struct Disable: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.Disable.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.Disable.Output
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
            try await client.disable(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}
