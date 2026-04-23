//
//  TimeSpan.swift
//  KurrentCore
//
//  Created by Grady Zhuo on 2024/3/22.
//

import Foundation

/// Duration expressed in either .NET ticks or milliseconds.
public enum TimeSpan: Sendable {
    /// Duration in 100-nanosecond .NET ticks.
    case ticks(Int64)
    /// Duration in milliseconds.
    case ms(Int32)
}
