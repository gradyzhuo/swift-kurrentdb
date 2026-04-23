//
//  PersistentSubscription.ConnectionInfo.swift
//  KurrentCore
//
//  Created by 卓俊諺 on 2025/1/12.
//

extension PersistentSubscription {
    /// Statistics for a single consumer connection to a persistent subscription.
    public struct ConnectionInfo: Sendable {
        /// Network address or identifier of the connected client.
        public let from: String
        /// Username of the authenticated client.
        public let username: String
        /// Average number of events delivered to this connection per second.
        public let averageItemsPerSecond: Int32
        /// Total number of events delivered over the lifetime of this connection.
        public let totalItems: Int64
        /// Number of events delivered since the last measurement snapshot.
        public let countSinceLastMeasurement: Int64
        /// Detailed throughput samples captured during the observation window.
        public let obervedMeasurements: [Measurement]
        /// Number of buffer slots currently available for new in-flight messages.
        public let availableSlots: Int32
        /// Number of messages currently awaiting acknowledgement from this connection.
        public let inFlightMessages: Int32
        /// Human-readable name assigned to this connection by the client.
        public let connectionName: String
    }
}
