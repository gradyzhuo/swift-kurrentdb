//
//  EventStore_Client_UUID+Additions.swift
//
//
//  Created by Ospark.org on 2023/10/24.
//

import Foundation
import GRPC
import GRPCSupport

public extension EventStore_Client_UUID {
    func toUUID() -> UUID? {
        switch value {
        case let .string(stringValue):
            return UUID(uuidString: stringValue)
        case let .structured(structuredValue):
            return UUID.from(integers: (structuredValue.leastSignificantBits, structuredValue.mostSignificantBits))
        case .none:
            return nil
        }
    }
}
