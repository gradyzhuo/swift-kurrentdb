//
//  ProjectionsClient.Enable.swift
//
//
//  Created by Grady Zhuo on 2023/11/27.
//

import Foundation
import GRPCCore
import GRPCEncapsulates

public struct Enable: UnaryUnary {
    public typealias Client = Projections.Service
    public typealias UnderlyingRequest = UnderlyingService.Method.Enable.Input
    public typealias UnderlyingResponse = UnderlyingService.Method.Enable.Output
    public typealias Response = DiscardedResponse<UnderlyingResponse>

    public let name: String
    public let options: Options
    
    package func requestMessage() throws -> UnderlyingRequest {
        return .with {
            $0.options = options.build()
            $0.options.name = name
        }
    }
    
    public func send(client: Client.UnderlyingClient, request: GRPCCore.ClientRequest<UnderlyingRequest>, callOptions: GRPCCore.CallOptions) async throws -> Response {
        return try await client.enable(request: request, options: callOptions){
            try handle(response: $0)
        }
    }
}

extension Enable {
    public struct Options: EventStoreOptions {
        public typealias UnderlyingMessage = UnderlyingRequest.Options

        var options: UnderlyingMessage

        public init() {
            options = .init()
        }

        public func build() -> UnderlyingMessage {
            options
        }
    }
}
