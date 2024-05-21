//
//  Projections.Statistics.swift
//
//
//  Created by Grady Zhuo on 2023/11/26.
//

import Foundation
import GRPCEncapsulates

extension ProjectionsClient {
    public struct Statistics: UnaryStream {
        public typealias Request = GenericGRPCRequest<EventStore_Client_Projections_StatisticsReq>

        public enum ModeOptions {
            case all
            case transient
            case continuous
            case oneTime
        }

        public let name: String
        public let options: Options

        package func build() throws -> Request.UnderlyingMessage {
            .with {
                $0.options = options.build()
                $0.options.name = name
            }
        }
    }
}

extension ProjectionsClient.Statistics {
    public struct Response: GRPCResponse {
        public typealias UnderlyingMessage = EventStore_Client_Projections_StatisticsResp

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

        public init(from message: EventStore_Client_Projections_StatisticsResp) throws {
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

extension ProjectionsClient.Statistics {
    public final class Options: EventStoreOptions {
        public typealias UnderlyingMessage = Request.UnderlyingMessage.Options

        var options: UnderlyingMessage
        var mode: ModeOptions {
            didSet {
                switch mode {
                case .all:
                    options.all = .init()
                case .transient:
                    options.transient = .init()
                case .continuous:
                    options.continuous = .init()
                case .oneTime:
                    options.oneTime = .init()
                }
            }
        }

        init(options: UnderlyingMessage = .init()) {
            self.options = options
            mode = .all
        }

        package func build() -> ProjectionsClient.Statistics.Request.UnderlyingMessage.Options {
            options
        }

        @discardableResult
        public func set(mode: ModeOptions) -> Self {
            self.mode = mode
            return self
        }
    }
}
