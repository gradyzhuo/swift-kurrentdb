//
//  EventStoreOptions.swift
//
//
//  Created by Grady Zhuo on 2023/10/31.
//

import Foundation
import SwiftProtobuf

package protocol FluentInterfaceOptions: Sendable {}

extension FluentInterfaceOptions {
    package func withCopy(handler: (_ options: inout Self) -> Void) -> Self {
        var copiedSelf = self
        handler(&copiedSelf)
        return copiedSelf
    }
}

package protocol EventStoreOptions: GRPCBridge, FluentInterfaceOptions {
    func build() -> UnderlyingMessage
}
