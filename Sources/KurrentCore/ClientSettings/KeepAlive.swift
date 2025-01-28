//
//  KeepAlive.swift
//  KurrentCore
//
//  Created by Grady Zhuo on 2024/1/1.
//

import Foundation

public struct KeepAlive: Sendable {
    public static let `default`: Self = .init(interval: 10.0, timeout: 10.0)

    var interval: TimeInterval
    var timeout: TimeInterval
}
