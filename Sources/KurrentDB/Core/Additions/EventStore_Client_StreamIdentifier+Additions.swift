//
//  EventStore_Client_StreamIdentifier+Additions.swift
//  KurrentCore
//
//  Created by Grady Zhuo on 2023/10/24.
//

import Foundation
import GRPCEncapsulates

extension EventStore_Client_StreamIdentifier {
    func toIdentifier() throws(KurrentError) -> StreamIdentifier {
        guard let name = String(data: streamName, encoding: .utf8) else {
            throw .internalParsingError(reason: "Stream name contains invalid UTF-8 data.")
        }
        return .init(name: name)
    }
}
