//
//  EventStore_Client_Streams_TombstoneResp+Additions.swift
//
//
//  Created by Grady Zhuo on 2023/11/2.
//

import Foundation
import GRPCEncapsulates

extension EventStore_Client_Streams_TombstoneResp.OneOf_PositionOption {
    typealias Represented = Stream.Position.Option

    func represented() -> Represented {
        switch self {
        case let .position(position):
            .position(.at(commitPosition: position.commitPosition, preparePosition: position.preparePosition))
        case .noPosition:
            .noPosition
        }
    }
}
