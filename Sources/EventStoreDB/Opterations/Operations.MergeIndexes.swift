//
//  Operations.MergeIndexes.swift
//
//
//  Created by Grady Zhuo on 2023/12/12.
//

import Foundation
import GRPCSupport

extension OperationsClient {
    public struct MergeIndexes: UnaryUnary {
        public typealias Request = EmptyRequest
        public typealias Response = EmptyResponse
    }
}
