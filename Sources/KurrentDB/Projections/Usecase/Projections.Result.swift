//
//  Projections.Result.swift
//  KurrentProjections
//
//  Created by Grady Zhuo on 2023/11/27.
//

import Foundation
import GRPCCore
import GRPCEncapsulates
import SwiftProtobuf

extension Projections {
    public struct Result: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.Result.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.Result.Output
        
        package static var name: String{
            get{
                "Projections.\(Self.self)"
            }
        }
        
        public let name: String
        public let options: Options

        package func requestMessage() throws -> UnderlyingRequest {
            .with {
                $0.options = options.build()
                $0.options.name = name
            }
        }

        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            do {
                let client = ServiceClient(wrapping: connection)
                return try await client.result(request: request, options: callOptions) {
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

extension Projections.Result {
    public struct Response: GRPCJSONDecodableResponse {
        package typealias UnderlyingMessage = UnderlyingResponse

        public private(set) var jsonValue: Google_Protobuf_Value

        package init(from message: UnderlyingMessage) throws {
            jsonValue = message.result
        }
    }

    public struct Options: EventStoreOptions {
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
