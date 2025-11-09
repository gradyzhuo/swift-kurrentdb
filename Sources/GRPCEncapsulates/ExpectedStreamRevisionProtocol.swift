//
//  ExpectedStreamRevisionProtocol.swift
//  GRPCEncapsulates
//
//  Created by Grady Zhuo on 2024/5/15.
//

import Foundation
import Generated

package protocol ExpectedStreamRevisionProtocol {
    static func any(_ value: EventStore_Client_Empty) -> Self
    static func noStream(_ value: EventStore_Client_Empty) -> Self
    static func streamExists(_ value: EventStore_Client_Empty) -> Self
    static func revision(_ value: UInt64) -> Self
}

extension EventStore_Client_Streams_AppendReq.Options.OneOf_ExpectedStreamRevision: ExpectedStreamRevisionProtocol {}
extension EventStore_Client_Streams_DeleteReq.Options.OneOf_ExpectedStreamRevision: ExpectedStreamRevisionProtocol {}
extension EventStore_Client_Streams_TombstoneReq.Options.OneOf_ExpectedStreamRevision: ExpectedStreamRevisionProtocol {}
