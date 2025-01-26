//
//  Update.swift
//  KurrentDB
//
//  Created by 卓俊諺 on 2025/1/16.
//

import Foundation
import GRPCCore
import GRPCEncapsulates

extension Users {
    public struct Update: UnaryUnary {
        package typealias ServiceClient = Client
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.Update.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.Update.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        let loginName: String
        let password: String
        let fullName: String
        let groups: [String]
        
        public init(loginName: String, password: String, fullName: String, groups: [String] = []) {
            self.loginName = loginName
            self.password = password
            self.fullName = fullName
            self.groups = groups
        }
        
        package func requestMessage() throws -> UnderlyingRequest {
            return .with {
                $0.options.loginName = loginName
                $0.options.password = password
                $0.options.fullName = fullName
                $0.options.groups = groups
            }
        }
        
        package func send(client: ServiceClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            return try await client.update(request: request, options: callOptions){
                try handle(response: $0)
            }
        }
    }
}
