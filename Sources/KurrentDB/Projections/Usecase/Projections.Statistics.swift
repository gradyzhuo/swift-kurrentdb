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
        public typealias Responses = AsyncThrowingStream<Response, Error>

        public enum Mode: Sendable {
            case any
            case transient
            case continuous
            case oneTime
        }

        public let options: Options

        public init(options: Options) {
            self.options = options
        }

        package func requestMessage() throws -> UnderlyingRequest {
            .with {
                switch options {
                case .specified(let name):
                    $0.options.name = name
                case .listAll(let mode):
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

        package func send(client: ServiceClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Responses {
            try await withThrowingTaskGroup(of: Void.self) { _ in
                let (stream, continuation) = AsyncThrowingStream.makeStream(of: Response.self)
                try await client.statistics(request: request, options: callOptions) {
                    for try await message in $0.messages {
                        try continuation.yield(handle(message: message))
                    }
                }
                continuation.finish()
                return stream
            }
        }
    }
}

extension Projections.Statistics {
    public struct Response: GRPCResponse {
        package typealias UnderlyingMessage = UnderlyingResponse

        public let coreProcessingTime: Int64
        public let version: Int64
        public let epoch: Int64
        public let effectiveName: String
        public let writesInProgress: Int32
        public let readsInProgress: Int32
        public let partitionsCached: Int32
        public let status: String
        public let stateReason: String
        public let name: String
        public let mode: String
        public let position: String
        public let progress: Float
        public let lastCheckpoint: String
        public let eventsProcessedAfterRestart: Int64
        public let checkpointStatus: String
        public let bufferedEvents: Int64
        public let writePendingEventsBeforeCheckpoint: Int32
        public let writePendingEventsAfterCheckpoint: Int32

        init(coreProcessingTime: Int64, version: Int64, epoch: Int64, effectiveName: String, writesInProgress: Int32, readsInProgress: Int32, partitionsCached: Int32, status: String, stateReason: String, name: String, mode: String, position: String, progress: Float, lastCheckpoint: String, eventsProcessedAfterRestart: Int64, checkpointStatus: String, bufferedEvents: Int64, writePendingEventsBeforeCheckpoint: Int32, writePendingEventsAfterCheckpoint: Int32) {
            self.coreProcessingTime = coreProcessingTime
            self.version = version
            self.epoch = epoch
            self.effectiveName = effectiveName
            self.writesInProgress = writesInProgress
            self.readsInProgress = readsInProgress
            self.partitionsCached = partitionsCached
            self.status = status
            self.stateReason = stateReason
            self.name = name
            self.mode = mode
            self.position = position
            self.progress = progress
            self.lastCheckpoint = lastCheckpoint
            self.eventsProcessedAfterRestart = eventsProcessedAfterRestart
            self.checkpointStatus = checkpointStatus
            self.bufferedEvents = bufferedEvents
            self.writePendingEventsBeforeCheckpoint = writePendingEventsBeforeCheckpoint
            self.writePendingEventsAfterCheckpoint = writePendingEventsAfterCheckpoint
        }

        package init(from message: UnderlyingResponse) throws {
            let details = message.details

            self.init(
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

extension Projections.Statistics{
    public enum Options : Sendable{
        case specified(name: String)
        case listAll(mode: Mode)
    }
}
