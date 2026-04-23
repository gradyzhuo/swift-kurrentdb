//
//  KeepAlive.swift
//  KurrentCore
//
//  Created by Grady Zhuo on 2024/1/1.
//

import Foundation

/// gRPC keep-alive timing configuration for a KurrentDB connection.
public struct KeepAlive: Sendable {
    /// Default keep-alive settings: 10-second interval and 10-second timeout.
    public static let `default`: Self = .init(interval: .seconds(10), timeout: .seconds(10))

    var interval: Duration
    var timeout: Duration

    /// Creates keep-alive settings with `Duration` values.
    ///
    /// - Parameters:
    ///   - interval: Time between keep-alive pings.
    ///   - timeout: Time to wait for a keep-alive acknowledgment before closing the connection.
    init(interval: Duration, timeout: Duration) {
        self.interval = interval
        self.timeout = timeout
    }

    /// Creates keep-alive settings from millisecond integer values.
    ///
    /// - Parameters:
    ///   - interval: Ping interval in milliseconds.
    ///   - timeout: Acknowledgment timeout in milliseconds.
    init(intervalMs interval: UInt64, timeoutMs timeout: UInt64) {
        self.interval = .milliseconds(interval)
        self.timeout = .milliseconds(timeout)
    }
}
