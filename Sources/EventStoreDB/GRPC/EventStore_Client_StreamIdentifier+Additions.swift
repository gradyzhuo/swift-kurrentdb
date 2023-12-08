//
//  EventStore_Client_StreamIdentifier+Additions.swift
//
//
//  Created by Ospark.org on 2023/10/24.
//

import Foundation

public extension EventStore_Client_StreamIdentifier {
    @available(macOS 10.15, *)
    func toIdentifier() -> Stream.Identifier {
        let name = String(data: streamName, encoding: .utf8)
        return .init(name: name!)
    }
}
