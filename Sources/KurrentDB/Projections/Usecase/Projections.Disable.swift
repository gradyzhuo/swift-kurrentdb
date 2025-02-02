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
        package typealias ServiceClient = Client
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.Disable.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.Disable.Output
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
            try await client.disable(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}

extension Projections.Disable {
    public struct Options: EventStoreOptions {
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
