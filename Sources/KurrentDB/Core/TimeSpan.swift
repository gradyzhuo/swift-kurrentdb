//
//  TimeSpan.swift
//  KurrentCore
//
//  Created by Grady Zhuo on 2024/3/22.
//

import Foundation

public enum TimeSpan: Sendable {
    case ticks(Int64)
    case ms(Int32)
}
