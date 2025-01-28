//
//  StreamRevision.swift
//  KurrentCore
//
//  Created by Grady Zhuo on 2024/5/21.
//

import Foundation

public struct StreamRevision: Sendable {
    public let value: UInt64

    package init(value: UInt64) {
        self.value = value
    }
}
