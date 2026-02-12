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

        package var methodDescriptor: GRPCCore.MethodDescriptor{
            get{
                ServiceClient.UnderlyingService.Method.Details.descriptor
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

        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions, completion: @Sendable @escaping ((any Error)?) -> Void) async throws -> Responses {
            let client = ServiceClient(wrapping: connection)
            return try await client.details(request: request, options: callOptions) {
                let (stream, continuation) = AsyncThrowingStream.makeStream(of: UserDetails.self)
                continuation.onTermination = { termination in
                    if case let .finished(error) = termination {
                        completion(error)
                    } else {
                        completion(nil)
                    }
                }
                do {
                    for try await message in $0.messages {
                        let response = try handle(message: message)
                        continuation.yield(response.userDetails)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                return stream
            }
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
