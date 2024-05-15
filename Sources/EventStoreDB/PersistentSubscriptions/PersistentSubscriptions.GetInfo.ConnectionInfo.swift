//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2024/5/15.
//

import Foundation

extension PersistentSubscriptionsClient.GetInfo {
    public struct ConnectionInfo {
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
