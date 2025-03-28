//
//  StreamRevisionRule.swift
//  KurrentCore
//
//  Created by Grady Zhuo on 2024/5/21.
//

import Foundation

public enum StreamRevision: Sendable {
    case any
    case noStream
    case streamExists
    case at(UInt64)
}
