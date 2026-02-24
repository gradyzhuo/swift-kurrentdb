//
//  Projection.Detail.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/2/23.
//

extension Projection {
    /// Detailed statistics for a single projection.
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

            self.name = name
            self.mode = mode
            self.coreProcessingTime = coreProcessingTime
            self.version = version
            self.epoch = epoch
            self.effectiveName = effectiveName
            self.writesInProgress = writesInProgress
            self.readsInProgress = readsInProgress
            self.partitionsCached = partitionsCached
            self.status = Projection.Status(rawValue: status)
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
