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
        
        package static var name: String{
            get{
                "Projections.\(Self.self)"
            }
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
    public struct Detail: Sendable {
        public let coreProcessingTime: Int64
        public let version: Int64
        public let epoch: Int64
        public let effectiveName: String
        public let writesInProgress: Int32
        public let readsInProgress: Int32
        public let partitionsCached: Int32
        public let status: Projection.Status
        public let stateReason: String
        public let name: String
        public let mode: Projection.Mode
        public let position: String
        public let progress: Float
        public let lastCheckpoint: String
        public let eventsProcessedAfterRestart: Int64
        public let checkpointStatus: String
        public let bufferedEvents: Int64
        public let writePendingEventsBeforeCheckpoint: Int32
        public let writePendingEventsAfterCheckpoint: Int32

        init(coreProcessingTime: Int64, version: Int64, epoch: Int64, effectiveName: String, writesInProgress: Int32, readsInProgress: Int32, partitionsCached: Int32, status: String, stateReason: String, name: String, mode: String, position: String, progress: Float, lastCheckpoint: String, eventsProcessedAfterRestart: Int64, checkpointStatus: String, bufferedEvents: Int64, writePendingEventsBeforeCheckpoint: Int32, writePendingEventsAfterCheckpoint: Int32) throws(KurrentError) {
            guard let mode = Projection.Mode(rawValue: mode) else {
                throw .initializationError(reason: "Invalid mode \(mode)")
            }

            guard let status = Projection.Status(name: status) else {
                throw .initializationError(reason: "Invalid status \(status)")
            }

            self.name = name
            self.mode = mode
            self.coreProcessingTime = coreProcessingTime
            self.version = version
            self.epoch = epoch
            self.effectiveName = effectiveName
            self.writesInProgress = writesInProgress
            self.readsInProgress = readsInProgress
            self.partitionsCached = partitionsCached
            self.status = status
            self.stateReason = stateReason
            self.position = position
            self.progress = progress
            self.lastCheckpoint = lastCheckpoint
            self.eventsProcessedAfterRestart = eventsProcessedAfterRestart
            self.checkpointStatus = checkpointStatus
            self.bufferedEvents = bufferedEvents
            self.writePendingEventsBeforeCheckpoint = writePendingEventsBeforeCheckpoint
            self.writePendingEventsAfterCheckpoint = writePendingEventsAfterCheckpoint
        }
    }
}

extension Projections.Statistics {
    public struct Response: GRPCResponse {
        package typealias UnderlyingMessage = UnderlyingResponse
        public let detail: Detail

        package init(from message: UnderlyingResponse) throws(KurrentError) {
            let details = message.details

            detail = try .init(
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
