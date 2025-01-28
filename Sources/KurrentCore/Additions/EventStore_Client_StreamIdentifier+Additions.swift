//
//  EventStore_Client_StreamIdentifier+Additions.swift
//  KurrentCore
//
//  Created by Grady Zhuo on 2023/10/24.
//

import Foundation
import GRPCEncapsulates

extension EventStore_Client_StreamIdentifier {
    func toIdentifier() -> StreamIdentifier {
        let name = String(data: streamName, encoding: .utf8)
        return .init(name: name!)
    }
}
