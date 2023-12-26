//
//  EventStore_Client_Streams_TombstoneResp+Additions.swift
//
//
//  Created by Ospark.org on 2023/11/2.
//

import Foundation
import GRPCSupport

@available(macOS 13.0, *)
extension EventStore_Client_Streams_TombstoneResp.OneOf_PositionOption {
    typealias Represented = StreamClient.Position.Option

    func represented() -> Represented {
        switch self {
        case let .position(position):
            return .position(.init(commit: position.commitPosition, prepare: position.preparePosition))
        case .noPosition:
            return .noPosition
        }
    }
}
