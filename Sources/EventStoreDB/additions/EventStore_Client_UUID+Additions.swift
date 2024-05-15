//
//  EventStore_Client_UUID+Additions.swift
//
//
//  Created by Grady Zhuo on 2023/10/24.
//

import Foundation
import GRPC
import GRPCEncapsulates

extension EventStore_Client_UUID {
    public func toUUID() -> UUID? {
        switch value {
        case let .string(stringValue):
            UUID(uuidString: stringValue)
        case let .structured(structuredValue):
            UUID.from(integers: (structuredValue.leastSignificantBits, structuredValue.mostSignificantBits))
        case .none:
            nil
        }
    }
}
