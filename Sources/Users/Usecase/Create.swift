//
//  UserClient.Create.swift
//
//
//  Created by Grady Zhuo on 2023/12/20.
//

import Foundation
import GRPCCore
import GRPCEncapsulates

public struct Create: UnaryUnary {
    public typealias Client = Users.Service
    public typealias UnderlyingRequest = UnderlyingService.Method.Create.Input
    public typealias UnderlyingResponse = UnderlyingService.Method.Create.Output
    public typealias Response = DiscardedResponse<UnderlyingResponse>

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
    
    
    public func send(client: Client.UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
        return try await client.create(request: request, options: callOptions){
            try handle(response: $0)
        }
    }
}

