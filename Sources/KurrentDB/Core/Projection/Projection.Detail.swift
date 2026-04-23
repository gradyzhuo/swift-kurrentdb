//
//  Projection.Detail.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/2/23.
//

extension Projection {
    /// Runtime statistics and configuration details for a single projection.
    public struct Detail: Sendable {
        /// Total CPU time consumed by the projection's core processing, in milliseconds.
        public let coreProcessingTime: Int64
        /// Current version of the projection definition.
        public let version: Int64
        /// Epoch counter, incremented on each restart.
        public let epoch: Int64
        /// Effective name used by the server for this projection.
        public let effectiveName: String
        /// Number of write operations currently in progress.
        public let writesInProgress: Int32
        /// Number of read operations currently in progress.
        public let readsInProgress: Int32
        /// Number of partition states currently cached in memory.
        public let partitionsCached: Int32
        /// Current operational status of the projection.
        public let status: Projection.Status
        /// Human-readable reason for the current state, if applicable.
        public let stateReason: String
        /// Name of the projection.
        public let name: String
        /// Mode under which the projection operates.
        public let mode: Projection.Mode
        /// Current position of the projection in the event log.
        public let position: String
        /// Percentage of the event log processed, from 0 to 100.
        public let progress: Float
        /// Position recorded at the most recent checkpoint.
        public let lastCheckpoint: String
        /// Number of events processed since the projection last restarted.
        public let eventsProcessedAfterRestart: Int64
        /// Current checkpoint write status.
        public let checkpointStatus: String
        /// Number of events buffered and awaiting processing.
        public let bufferedEvents: Int64
        /// Number of events pending write before the next checkpoint.
        public let writePendingEventsBeforeCheckpoint: Int32
        /// Number of events pending write after the most recent checkpoint.
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
