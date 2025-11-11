//
//  Users.Details.swift
//  KurrentUsers
//
//  Created by Grady Zhuo on 2023/12/20.
//

import Foundation
import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix

extension Users {
    public struct Details: UnaryStream {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.Details.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.Details.Output
        package typealias Responses = AsyncThrowingStream<UserDetails, any Error>

        public let loginName: String

        public init(loginName: String) {
            self.loginName = loginName
        }

        package func requestMessage() throws -> UnderlyingRequest {
            .with {
                $0.options.loginName = loginName
            }
        }

        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions, completion: @Sendable @escaping ((any Error)?)->Void) async throws -> Responses {
            let (stream, continuation) = AsyncThrowingStream.makeStream(of: UserDetails.self)
            continuation.onTermination = { termination in
                if case .finished(let error) = termination, let error {
                    completion(error)
                }
                completion(nil)
            }
            Task{
                let client = ServiceClient(wrapping: connection)
                try await client.details(request: request, options: callOptions) {
                    do{
                        for try await message in $0.messages {
                            let response = try handle(message: message)
                            continuation.yield(response.userDetails)
                        }
                        continuation.finish()
                    }catch{
                        continuation.finish(throwing: error)
                    }
                }
            }

            return stream
        }
    }
}

extension Users.Details {
    public struct Response: GRPCResponse {
        package typealias UnderlyingMessage = UnderlyingResponse

        let userDetails: UserDetails

        package init(from message: UnderlyingMessage) throws {
            userDetails = try .init(from: message.userDetails)
        }
    }
}
