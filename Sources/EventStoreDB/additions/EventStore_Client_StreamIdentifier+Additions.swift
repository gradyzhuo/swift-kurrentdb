//
//  EventStore_Client_StreamIdentifier+Additions.swift
//
//
//  Created by Grady Zhuo on 2023/10/24.
//

import Foundation
import GRPCSupport

extension EventStore_Client_StreamIdentifier {
    func toIdentifier() -> Stream.Identifier {
        let name = String(data: streamName, encoding: .utf8)
        return .init(name: name!)
    }
}
