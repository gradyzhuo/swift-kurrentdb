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

        package func send(client: ServiceClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            try await client.state(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}

extension Projections.State {
    public struct Response: GRPCJSONDecodableResponse {
        package typealias UnderlyingMessage = UnderlyingResponse

        public private(set) var jsonValue: SwiftProtobuf.Google_Protobuf_Value

        package init(from message: UnderlyingMessage) throws {
            jsonValue = message.state
        }
    }

    public struct Options: EventStoreOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        var partition: String?

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
