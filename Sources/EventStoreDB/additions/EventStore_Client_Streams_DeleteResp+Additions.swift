//
//  EventStore_Client_Streams_DeleteResp+Additions.swift
//
//
//  Created by Grady Zhuo on 2023/10/31.
//

import Foundation
import GRPCEncapsulates

extension EventStore_Client_Streams_DeleteResp.OneOf_PositionOption {
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
