//
//  PersistentSubscription.Measurement.swift
//  KurrentCore
//
//  Created by 卓俊諺 on 2025/1/12.
//

extension PersistentSubscription {
    /// A single named throughput sample reported by the server.
    public struct Measurement: Sendable {
        /// Name of the metric being measured.
        public let key: String
        /// Numeric value of the measurement at the time of sampling.
        public let value: Int64
    }
}
