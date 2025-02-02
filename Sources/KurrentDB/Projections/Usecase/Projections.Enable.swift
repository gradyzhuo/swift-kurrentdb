//
//  Projections.Enable.swift
//  KurrentProjections
//
//  Created by Grady Zhuo on 2023/11/27.
//

import Foundation
import GRPCCore
import GRPCEncapsulates

extension Projections {
    public struct Enable: UnaryUnary {
        package typealias ServiceClient = Client
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.Enable.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.Enable.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        public let name: String
        public let options: Options

        package func requestMessage() throws -> UnderlyingRequest {
            .with {
                $0.options = options.build()
                $0.options.name = name
            }
        }

        package func send(client: ServiceClient, request: GRPCCore.ClientRequest<UnderlyingRequest>, callOptions: GRPCCore.CallOptions) async throws -> Response {
            try await client.enable(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}

extension Projections.Enable {
    public struct Options: EventStoreOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        public init() {}

        package func build() -> UnderlyingMessage {
            .init()
        }
    }
}
