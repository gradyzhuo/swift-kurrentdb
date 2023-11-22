//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/10/24.
//

import Foundation
import GRPC

extension EventStore_Client_UUID {
    
    public func toUUID() -> UUID? {
        switch self.value {
        case .string(let stringValue):
            return UUID(uuidString: stringValue)
        case .structured(let structuredValue):
            return UUID.from(integers: (structuredValue.leastSignificantBits, structuredValue.mostSignificantBits))
        case .none:
            return nil
        }
        
    }
    
    
}
