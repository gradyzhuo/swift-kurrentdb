//
//  PersistentSubscriptionsClient.GetInfo.Measurement.swift
//
//
//  Created by Grady Zhuo on 2024/5/15.
//

import Foundation

extension PersistentSubscriptionsClient.GetInfo {
    public struct Measurement: Sendable {
        public let key: String
        public let value: Int64
    }
}
