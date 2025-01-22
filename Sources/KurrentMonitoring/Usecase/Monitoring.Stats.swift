//
//  Monitoring.Stats.swift
//
//
//  Created by Grady Zhuo on 2023/12/11.
//

import GRPCCore
import GRPCEncapsulates

public struct Stats: UnaryStream {
    public typealias Client = Service
    public typealias UnderlyingRequest = UnderlyingService.Method.Stats.Input
    public typealias UnderlyingResponse = UnderlyingService.Method.Stats.Output
    public typealias Responses = AsyncThrowingStream<Response, any Error>

    public let useMetadata: Bool
    public let refreshTimePeriodInMs: UInt64
    
    public init(useMetadata: Bool = false, refreshTimePeriodInMs: UInt64 = 10000) {
        self.useMetadata = useMetadata
        self.refreshTimePeriodInMs = refreshTimePeriodInMs
    }

    package func requestMessage() throws -> UnderlyingService.Method.Stats.Input {
        return .with {
            $0.useMetadata = useMetadata
            $0.refreshTimePeriodInMs = refreshTimePeriodInMs
        }
    }
    
    public func send(client: Client.UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Responses {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: Response.self)
        Task{
            try await client.stats(request: request, options: callOptions) {
                for try await message in $0.messages {
                    try continuation.yield(.init(from: message))
                }
            }
        }
        return stream
    }
}

extension Stats {
    public struct Response: GRPCResponse {
        public typealias UnderlyingMessage = UnderlyingResponse

        var stats: [String: String]

        public init(from message: UnderlyingMessage) throws {
            stats = message.stats
        }
    }
}
