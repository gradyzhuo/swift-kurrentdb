//
//  Projections.State.swift
//  KurrentProjections
//
//  Created by Grady Zhuo on 2023/11/27.
//

import Foundation
import GRPCCore
import GRPCEncapsulates
import SwiftProtobuf

extension Projections {
    public struct State: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.State.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.State.Output

        package var methodDescriptor: GRPCCore.MethodDescriptor {
            ServiceClient.UnderlyingService.Method.State.descriptor
        }

        package static var name: String {
            "Projections.\(Self.self)"
        }

        public let name: String
        public let options: Options

        public init(name: String, options: Options) {
            self.name = name
            self.options = options
        }

        package func requestMessage() throws -> UnderlyingRequest {
            .with {
                $0.options = options.build()
                $0.options.name = name
            }
        }

        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            do {
                let client = ServiceClient(wrapping: connection)
                return try await client.state(request: request, options: callOptions) {
                    try handle(response: $0)
                }
            } catch let error as RPCError {
                if error.message.contains("NotFound") {
                    throw KurrentError.resourceNotFound(reason: "Projection \(name) not found.")
                }

                throw try KurrentError.grpc(code: error.unpackGoogleRPCStatus(), reason: "Unknown error occurred.")
            } catch {
                throw KurrentError.serverError("Unknown error occurred, cause: \(error)")
            }
        }
    }
}

extension Projections.State {
    public struct Response: GRPCJSONDecodableResponse {
        package typealias UnderlyingMessage = UnderlyingResponse

        package var jsonValue: SwiftProtobuf.Google_Protobuf_Value

        package init(from message: UnderlyingMessage) throws {
            jsonValue = message.state
        }
    }

    public struct Options: CommandOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        public private(set) var partition: String?

        public init() {
            partition = nil
        }

        public func partition(_ partition: String) -> Self {
            withCopy { options in
                options.partition = partition
            }
        }

        package func build() -> UnderlyingMessage {
            .with {
                if let partition {
                    $0.partition = partition
                }
            }
        }
    }
}
