//
//  PersistentSubscriptions.GetInfo.Measurement.swift
//
//
//  Created by 卓俊諺 on 2024/5/15.
//

import Foundation

extension PersistentSubscriptionsClient.GetInfo {
    public struct Measurement {
        public let key: String
        public let value: Int64
    }
}
