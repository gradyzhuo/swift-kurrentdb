//
//  Operations.ResignNode.swift
//
//
//  Created by Grady Zhuo on 2023/12/12.
//

import Foundation
import GRPCEncapsulates

extension OperationsClient {
    public struct ResignNode: UnaryUnary {
        public typealias Request = EmptyRequest
        public typealias Response = EmptyResponse
    }
}
