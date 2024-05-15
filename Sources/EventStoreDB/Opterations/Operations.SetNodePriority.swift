//
//  Operations.SetNodePriority.swift
//
//
//  Created by Grady Zhuo on 2023/12/12.
//

import Foundation
import GRPCEncapsulates

extension OperationsClient {
    public struct SetNodePriority: UnaryUnary {
        public typealias Request = GenericGRPCRequest<EventStore_Client_Operations_SetNodePriorityReq>
        public typealias Response = EmptyResponse

        let priority: Int32

        public func build() throws -> Request.UnderlyingMessage {
            .with {
                $0.priority = priority
            }
        }
    }
}
