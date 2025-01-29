//
//  StartScavenge.swift
//  KurrentOperations
//
//  Created by Grady Zhuo on 2023/12/12.
//

import GRPCCore
import GRPCEncapsulates

extension Operations {
    public struct StartScavenge: UnaryUnary {
        package typealias ServiceClient = Client
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.StartScavenge.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.StartScavenge.Output
        public typealias Response = ScavengeResponse

        public let threadCount: Int32
        public let startFromChunk: Int32

        public init(threadCount: Int32, startFromChunk: Int32) {
            self.threadCount = threadCount
            self.startFromChunk = startFromChunk
        }

        package func requestMessage() throws -> UnderlyingRequest {
            .with {
                $0.options = .with {
                    $0.threadCount = threadCount
                    $0.startFromChunk = startFromChunk
                }
            }
        }

        package func send(client: ServiceClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            try await client.startScavenge(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}
