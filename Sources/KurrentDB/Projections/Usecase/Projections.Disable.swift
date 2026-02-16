//
//  Projections.Disable.swift
//  KurrentProjections
//
//  Created by Grady Zhuo on 2023/11/27.
//

import Foundation
import GRPCCore
import GRPCEncapsulates

extension Projections {
    public struct Disable: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.Disable.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.Disable.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        package var methodDescriptor: GRPCCore.MethodDescriptor {
            ServiceClient.UnderlyingService.Method.Disable.descriptor
        }

        package static var name: String {
            "Projections.\(Self.self)"
        }

        public let name: String
        public let options: Options

        package func requestMessage() throws -> UnderlyingRequest {
            .with {
                $0.options = options.build()
                $0.options.name = name
            }
        }

        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws(KurrentError) -> Response {
            let client = ServiceClient(wrapping: connection)
            do {
                return try await client.disable(request: request, options: callOptions) {
                    try handle(response: $0)
                }
            } catch let error as RPCError {
                if error.message.contains("NotFound") {
                    throw .resourceNotFound(reason: "Projection \(name) not found.")
                }
                throw .grpcError(cause: error)
            } catch {
                throw .serverError("Unknown error occurred, cause: \(error)")
            }
        }
    }
}

extension Projections.Disable {
    public struct Options: CommandOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        var writeCheckpoint: Bool

        public init(writeCheckpoint: Bool = false) {
            self.writeCheckpoint = writeCheckpoint
        }

        package func build() -> UnderlyingMessage {
            .with {
                $0.writeCheckpoint = writeCheckpoint
            }
        }

        @discardableResult
        public func writeCheckpoint(enabled: Bool) -> Self {
            withCopy { options in
                options.writeCheckpoint = enabled
            }
        }
    }
}
