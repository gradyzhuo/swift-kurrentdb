//
//  StreamRevisionRule.swift
//  KurrentCore
//
//  Created by Grady Zhuo on 2024/5/21.
//

import Foundation

extension StreamRevision {
    public enum Rule: Sendable {
        case any
        case noStream
        case streamExists
        case revision(UInt64)
    }
}
