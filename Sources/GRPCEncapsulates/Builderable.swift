//
//  EventStoreOptions.swift
//
//
//  Created by Grady Zhuo on 2023/10/31.
//

import Foundation
import SwiftProtobuf

package protocol Builderable: Sendable {}

extension Builderable {
    package func withCopy(handler: (_ copied: inout Self) -> Void) -> Self {
        var copiedSelf = self
        handler(&copiedSelf)
        return copiedSelf
    }
}

package protocol EventStoreOptions: GRPCBridge, Builderable {
    func build() -> UnderlyingMessage
}
