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

        package func send(client: ServiceClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            try await client.reset(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}

extension Projections.Reset {
    public struct Options: EventStoreOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        public private(set) var writeCheckpoint: Bool

        public init(writeCheckpoint: Bool = false) {
            self.writeCheckpoint = writeCheckpoint
        }

        public func writeCheckpoint(enable: Bool) -> Self {
            withCopy { options in
                options.writeCheckpoint = enable
            }
        }

        package func build() -> UnderlyingRequest.Options {
            .with {
                $0.writeCheckpoint = writeCheckpoint
            }
        }
    }
}
