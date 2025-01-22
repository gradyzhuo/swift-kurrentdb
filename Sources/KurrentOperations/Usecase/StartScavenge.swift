//
//  Operations.StartScavenge.swift
//
//
//  Created by Grady Zhuo on 2023/12/12.
//

import GRPCCore
import GRPCEncapsulates

public struct StartScavenge: UnaryUnary {
    public typealias Client = Service
    public typealias UnderlyingRequest = UnderlyingService.Method.StartScavenge.Input
    public typealias UnderlyingResponse = UnderlyingService.Method.StartScavenge.Output
    public typealias Response = ScavengeResponse

    public let threadCount: Int32
    public let startFromChunk: Int32
    
    public init(threadCount: Int32, startFromChunk: Int32) {
        self.threadCount = threadCount
        self.startFromChunk = startFromChunk
    }

    package func requestMessage() throws -> UnderlyingService.Method.StartScavenge.Input {
        return .with {
            $0.options = .with {
                $0.threadCount = threadCount
                $0.startFromChunk = startFromChunk
            }
        }
    }
    
    public func send(client: Client.UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
        return try await client.startScavenge(request: request, options: callOptions){
            try handle(response: $0)
        }
    }
}
