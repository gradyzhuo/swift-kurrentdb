//
//  StreamRevisionRule.swift
//
//
//  Created by Grady Zhuo on 2024/5/21.
//

import Foundation

public enum StreamRevisionRule: Sendable {
    case any
    case noStream
    case streamExists
    case revision(UInt64)
}
