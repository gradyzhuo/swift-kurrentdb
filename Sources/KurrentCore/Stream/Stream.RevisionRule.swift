//
//  Stream.RevisionRule.swift
//
//
//  Created by Grady Zhuo on 2024/5/21.
//

import Foundation

extension Stream {
    public enum RevisionRule: Sendable {
        case any
        case noStream
        case streamExists
        case revision(UInt64)
    }
}
