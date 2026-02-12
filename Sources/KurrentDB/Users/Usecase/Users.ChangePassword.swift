//
//  Users.ChangePassword.swift
//  KurrentUsers
//
//  Created by 卓俊諺 on 2025/1/16.
//

import Foundation
import GRPCCore
import GRPCEncapsulates

extension Users {
    public struct ChangePassword: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.ChangePassword.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.ChangePassword.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        package var methodDescriptor: GRPCCore.MethodDescriptor{
            get{
                ServiceClient.UnderlyingService.Method.ChangePassword.descriptor
            }
        }

        package static var name: String{
            get{
                "Users.\(Self.self)"
            }
        }
        
        public let loginName: String
        private let currentPassword: String
        private let newPassword: String

        public init(loginName: String, currentPassword: String, newPassword: String) {
            self.loginName = loginName
            self.currentPassword = currentPassword
            self.newPassword = newPassword
        }

        package func requestMessage() throws -> UnderlyingRequest {
            .with {
                $0.options.loginName = loginName
                $0.options.currentPassword = currentPassword
                $0.options.newPassword = newPassword
            }
        }

        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            let client = ServiceClient(wrapping: connection)
            return try await client.changePassword(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}
