//
//  Projections.Reset.swift
//  KurrentProjections
//
//  Created by Grady Zhuo on 2023/12/5.
//

import Foundation
import GRPCCore
import GRPCEncapsulates

extension Projections {
    public struct Reset: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.Reset.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.Reset.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        package var methodDescriptor: GRPCCore.MethodDescriptor {
            ServiceClient.UnderlyingService.Method.Reset.descriptor
        }

        package static var name: String {
            "Projections.\(Self.self)"
        }

        let name: String
        let options: Options

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

        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws(KurrentError) -> Response {
            try await withRethrowingError(usage: Self.name) {
                let client = ServiceClient(wrapping: connection)
                return try await client.reset(request: request, options: callOptions) {
                    try handle(response: $0)
                }
            }
        }
    }
}

extension Projections.Reset {
    public struct Options: CommandOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        public var writeCheckpoint: Bool

        public init() {
            writeCheckpoint = true
        }

        package func build() -> UnderlyingRequest.Options {
            .with {
                $0.writeCheckpoint = writeCheckpoint
            }
        }
    }
}
