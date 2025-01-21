//
//  PersistentSubscription.ConnectionInfo.swift
//  KurrentDB
//
//  Created by 卓俊諺 on 2025/1/12.
//

extension PersistentSubscription {
    public struct ConnectionInfo: Sendable {
        public let from: String
        public let username: String
        public let averageItemsPerSecond: Int32
        public let totalItems: Int64
        public let countSinceLastMeasurement: Int64
        public let obervedMeasurements: [Measurement]
        public let availableSlots: Int32
        public let inFlightMessages: Int32
        public let connectionName: String
    }
}
