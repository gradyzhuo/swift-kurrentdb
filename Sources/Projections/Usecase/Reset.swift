//
//  ProjectionsClient.Reset.swift
//
//
//  Created by Grady Zhuo on 2023/12/5.
//

import Foundation
import GRPCCore
import GRPCEncapsulates

public struct Reset: UnaryUnary {
    public typealias Client = Projections.Service
    public typealias UnderlyingRequest = UnderlyingService.Method.Reset.Input
    public typealias UnderlyingResponse = UnderlyingService.Method.Reset.Output
    public typealias Response = DiscardedResponse<UnderlyingResponse>

    let name: String
    let options: Options
    
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
    
    public func send(client: Client.UnderlyingClient, request: GRPCCore.ClientRequest<UnderlyingRequest>, callOptions: GRPCCore.CallOptions) async throws -> Response {
        return try await client.reset(request: request, options: callOptions){
            try handle(response: $0)
        }
    }
}

extension Reset {
    public struct Options: EventStoreOptions {
        public typealias UnderlyingMessage = UnderlyingRequest.Options

        var writeCheckpoint: Bool = false

        public func writeCheckpoint(enable: Bool) -> Self {
            withCopy { options in
                options.writeCheckpoint = enable
            }
        }

        package func build() -> Reset.UnderlyingRequest.Options {
            return .with {
                $0.writeCheckpoint = writeCheckpoint
            }
        }
    }
}
