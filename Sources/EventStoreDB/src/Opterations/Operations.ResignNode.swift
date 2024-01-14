//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/12/12.
//

import Foundation
import GRPCSupport


extension OperationsClient {
    
    public struct ResignNode: UnaryUnary {
        public typealias Request = EmptyRequest
        public typealias Response = EmptyResponse
    }
    
}
