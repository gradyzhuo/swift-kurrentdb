//
//  Buildable.swift
//
//
//  Created by Grady Zhuo on 2023/10/31.
//

import Foundation
import SwiftProtobuf

package protocol Buildable: Sendable {}

extension Buildable {
    package func withCopy(handler: (_ copied: inout Self) -> Void) -> Self {
        var copiedSelf = self
        handler(&copiedSelf)
        return copiedSelf
    }
}

package protocol EventStoreOptions: GRPCBridge, Buildable {
    func build() -> UnderlyingMessage
}
