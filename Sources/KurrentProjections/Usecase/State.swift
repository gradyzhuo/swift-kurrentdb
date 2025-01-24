//
//  ProjectionsClient.State.swift
//
//
//  Created by Grady Zhuo on 2023/11/27.
//

import Foundation
import GRPCCore
import GRPCEncapsulates
import SwiftProtobuf

extension Projections {
    public struct State: UnaryUnary {
        public typealias ServiceClient = Client
        public typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.State.Input
        public typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.State.Output

        public let name: String
        public let options: Options
        
        public init(name: String, options: Options) {
            self.name = name
            self.options = options
        }

        package func requestMessage() throws -> UnderlyingRequest {
            return .with {
                $0.options = options.build()
                $0.options.name = name
            }
        }
        
        public func send(client: ServiceClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            return try await client.state(request: request, options: callOptions){
                try handle(response: $0)
            }
        }

    }
}

extension Projections.State {
    public struct Response: GRPCJSONDecodableResponse {
        public typealias UnderlyingMessage = UnderlyingResponse

        public private(set) var jsonValue: SwiftProtobuf.Google_Protobuf_Value

        public init(from message: UnderlyingMessage) throws {
            jsonValue = message.state
        }
    }

    public struct Options: EventStoreOptions {
        public typealias UnderlyingMessage = UnderlyingRequest.Options

        var partition: String?

        public func partition(_ partition: String) -> Self {
            withCopy { options in
                options.partition = partition
            }
        }

        package func build() -> UnderlyingMessage {
            return .with {
                if let partition {
                    $0.partition = partition
                }
            }
        }
    }
}
