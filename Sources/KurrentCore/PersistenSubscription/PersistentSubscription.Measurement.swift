//
//  PersistentSubscription.Measurement.swift
//  KurrentDB
//
//  Created by 卓俊諺 on 2025/1/12.
//

extension PersistentSubscription{
    public struct Measurement: Sendable {
        public let key: String
        public let value: Int64
    }
}
