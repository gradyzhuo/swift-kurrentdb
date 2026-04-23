//
//  Monitoring.Stats.swift
//  KurrentMonitoring
//
//  Created by Grady Zhuo on 2023/12/11.
//

import GRPCCore
import GRPCEncapsulates

extension Monitoring {
    /// Usecase that opens a server-streaming stats RPC and yields periodic snapshots.
    public struct Stats: UnaryStream {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.Stats.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.Stats.Output
        public typealias Responses = AsyncThrowingStream<Response, any Error>

        package var methodDescriptor: GRPCCore.MethodDescriptor {
            ServiceClient.UnderlyingService.Method.Stats.descriptor
        }

        package static var name: String {
            "Monitoring.\(Self.self)"
        }

        /// Whether to include metadata fields in each stats snapshot.
        public let useMetadata: Bool
        /// Interval between consecutive snapshots in milliseconds.
        public let refreshTimePeriodInMs: UInt64

        public init(useMetadata: Bool = false, refreshTimePeriodInMs: UInt64 = 10000) {
            self.useMetadata = useMetadata
            self.refreshTimePeriodInMs = refreshTimePeriodInMs
        }

        package func requestMessage() throws -> UnderlyingRequest {
            .with {
                $0.useMetadata = useMetadata
                $0.refreshTimePeriodInMs = refreshTimePeriodInMs
            }
        }

        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions, completion: @Sendable @escaping ((any Error)?) -> Void) async throws -> Responses {
            let client = ServiceClient(wrapping: connection)
            let (stream, continuation) = AsyncThrowingStream.makeStream(of: Response.self)
            
            let task = Task {
                do {
                    try await client.stats(request: request, options: callOptions) {
                        do {
                            for try await message in $0.messages {
                                try continuation.yield(handle(message: message))
                            }
                            continuation.finish()
                        } catch {
                            continuation.finish(throwing: error)
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { termination in
                task.cancel()
                if case let .finished(error) = termination {
                    completion(error)
                } else {
                    completion(nil)
                }
            }
            return stream
        }
    }
}

extension Monitoring.Stats {
    /// Single server statistics snapshot decoded from a gRPC response message.
    public struct Response: GRPCResponse {
        package typealias UnderlyingMessage = UnderlyingResponse

        /// Key-value map of server metric names to their current values.
        public var stats: [String: String]

        package init(from message: UnderlyingMessage) throws {
            stats = message.stats
        }
    }
}
