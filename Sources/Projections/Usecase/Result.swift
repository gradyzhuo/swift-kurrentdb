//
//  ProjectionsClient.Result.swift
//
//
//  Created by Grady Zhuo on 2023/11/27.
//

import Foundation
import GRPCCore
import GRPCEncapsulates
import SwiftProtobuf

public struct Result: UnaryUnary {
    public typealias Client = Projections.Service
    public typealias UnderlyingRequest = UnderlyingService.Method.Result.Input
    public typealias UnderlyingResponse = UnderlyingService.Method.Result.Output

    public let name: String
    public let options: Options
    
    package func requestMessage() throws -> UnderlyingRequest {
        return .with {
            $0.options = options.build()
            $0.options.name = name
        }
    }
    
    public func send(client: Client.UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
        return try await client.result(request: request, options: callOptions){
            try handle(response: $0)
        }
    }
}

extension Result {
    public struct Response: GRPCJSONDecodableResponse {
        public typealias UnderlyingMessage = UnderlyingResponse

        public private(set) var jsonValue: Google_Protobuf_Value

        public init(from message: UnderlyingMessage) throws {
            jsonValue = message.result
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
