//
//  KeepAlive.swift
//  KurrentCore
//
//  Created by Grady Zhuo on 2024/1/1.
//

import Foundation

public struct KeepAlive: Sendable {
    public static let `default`: Self = .init(interval: .microseconds(10000), timeout: .microseconds(10000))

    var interval: Duration
    var timeout: Duration
    
    init(interval: Duration, timeout: Duration) {
        self.interval = interval
        self.timeout = timeout
    }
    
    init(intervalMs interval: UInt64, timeoutMs timeout: UInt64) {
        self.interval = .microseconds(interval)
        self.timeout = .microseconds(timeout)
    }
}
