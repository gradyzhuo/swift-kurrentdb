//
//  UserClient.Details.swift
//
//
//  Created by Grady Zhuo on 2023/12/20.
//

import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2Posix
import GRPCEncapsulates

public struct Details: UnaryStream {
    public typealias Client = Users.Service
    public typealias UnderlyingRequest = UnderlyingService.Method.Details.Input
    public typealias UnderlyingResponse = UnderlyingService.Method.Details.Output
    public typealias Responses = AsyncThrowingStream<UserDetails, any Error>

    public let loginName: String

    public init(loginName: String) {
        self.loginName = loginName
    }
    
    package func requestMessage() throws -> UnderlyingRequest {
        return .with {
            $0.options.loginName = loginName
        }
    }
    
    public func send(client: Client.UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Responses {
        return try await withThrowingDiscardingTaskGroup { group in
            let (stream, continuation) = AsyncThrowingStream.makeStream(of: UserDetails.self)
            try await client.details(request: request, options: callOptions) {
                for try await message in $0.messages {
                    let response = try handle(message: message)
                    continuation.yield(response.userDetails)
                }
            }
            continuation.finish()
            return stream
        }
    }
    
    
    
}

extension Details {
    public struct Response: GRPCResponse {
        public typealias UnderlyingMessage = UnderlyingResponse

        let userDetails: UserDetails

        public init(from message: UnderlyingMessage) throws {
            userDetails = try .init(from: message.userDetails)
        }
    }
}
