//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/12/12.
//

import Foundation
import GRPCSupport

@available(macOS 10.15, *)
extension Operations {
    
    public struct ResignNode: UnaryUnary {
        public typealias Request = EmptyRequest
        public typealias Response = EmptyResponse
    }
    
}
