//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/10/24.
//

import Foundation


extension EventStore_Client_StreamIdentifier {
    @available(macOS 10.15, *)
    public func toIdentifier() -> Stream.Identifier {
        let name = String(data: self.streamName, encoding: .utf8)
        return .init(name: name!)
    }
}
