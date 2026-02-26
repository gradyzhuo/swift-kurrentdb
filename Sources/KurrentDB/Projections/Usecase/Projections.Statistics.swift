//
//  Projections.Statistics.swift
//  KurrentProjections
//
//  Created by Grady Zhuo on 2023/11/26.
//

import Foundation
import GRPCCore
import GRPCEncapsulates

extension Projections {
    public struct Statistics: UnaryStream {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.Statistics.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.Statistics.Output
        public typealias Responses = AsyncThrowingStream<Response, any Error>

        package var methodDescriptor: GRPCCore.MethodDescriptor {
            ServiceClient.UnderlyingService.Method.Statistics.descriptor
        }

        package static var name: String {
            "Projections.\(Self.self)"
        }

        public let options: Options

        public init(options: Options) {
            self.options = options
        }

        package func requestMessage() throws -> UnderlyingRequest {
            .with {
                switch options {
                case let .specified(name):
                    $0.options.name = name
                case let .listAll(mode):
                    switch mode {
                    case .any:
                        $0.options.all = .init()
                    case .continuous:
                        $0.options.continuous = .init()
                    case .oneTime:
                        $0.options.oneTime = .init()
                    case .transient:
                        $0.options.transient = .init()
                    }
                }
            }
        }

        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions, completion: @Sendable @escaping ((any Error)?) -> Void) async throws -> Responses {
            let client = ServiceClient(wrapping: connection)
            return try await client.statistics(request: request, options: callOptions) {
                let (stream, continuation) = AsyncThrowingStream.makeStream(of: Response.self)
                continuation.onTermination = { termination in
                    if case let .finished(error) = termination {
                        completion(error)
                    } else {
                        completion(nil)
                    }
                }
                do {
                    for try await message in $0.messages {
                        try continuation.yield(handle(message: message))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                return stream
            }
        }
    }
}

extension Projections.Statistics {
    public struct Response: GRPCResponse {
        package typealias UnderlyingMessage = UnderlyingResponse
        public let detail: Projection.Detail

        package init(from message: UnderlyingResponse) throws(KurrentError) {
            let details = message.details

            self.detail = try .init(
                coreProcessingTime: details.coreProcessingTime,
                version: details.version,
                epoch: details.epoch,
                effectiveName: details.effectiveName,
                writesInProgress: details.writesInProgress,
                readsInProgress: details.readsInProgress,
                partitionsCached: details.partitionsCached,
                status: details.status,
                stateReason: details.stateReason,
                name: details.name,
                mode: details.mode,
                position: details.position,
                progress: details.progress,
                lastCheckpoint: details.lastCheckpoint,
                eventsProcessedAfterRestart: details.eventsProcessedAfterRestart,
                checkpointStatus: details.checkpointStatus,
                bufferedEvents: details.bufferedEvents,
                writePendingEventsBeforeCheckpoint: details.writePendingEventsBeforeCheckpoint,
                writePendingEventsAfterCheckpoint: details.writePendingEventsAfterCheckpoint
            )
        }
    }
}

extension Projections.Statistics {
    public enum Options: Sendable {
        case specified(name: String)
        case listAll(mode: Projection.Mode)
    }
}
