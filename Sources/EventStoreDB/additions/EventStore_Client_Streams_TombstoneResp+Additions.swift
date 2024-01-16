//
//  EventStore_Client_Streams_TombstoneResp+Additions.swift
//
//
//  Created by Grady Zhuo on 2023/11/2.
//

import Foundation
import GRPCSupport

extension EventStore_Client_Streams_TombstoneResp.OneOf_PositionOption {
    typealias Represented = StreamClient.Position.Option

    func represented() -> Represented {
        switch self {
        case let .position(position):
            .position(.init(commit: position.commitPosition, prepare: position.preparePosition))
        case .noPosition:
            .noPosition
        }
    }
}
