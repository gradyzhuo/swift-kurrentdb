//
//  Enable.swift
//  KurrentDB
//
//  Created by 卓俊諺 on 2025/1/16.
//
import Foundation
import GRPCCore
import GRPCEncapsulates

extension Users {
    public struct Enable: UnaryUnary {
        public typealias ServiceClient = Client
        public typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.Enable.Input
        public typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.Enable.Output
        public typealias Response = DiscardedResponse<UnderlyingResponse>

        public let loginName: String
        
        public init(loginName: String) {
            self.loginName = loginName
        }
        
        package func requestMessage() throws -> UnderlyingRequest {
            return .with {
                $0.options.loginName = loginName
            }
        }
        
        public func send(client: ServiceClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            return try await client.enable(request: request, options: callOptions){
                try handle(response: $0)
            }
        }
    }
}
