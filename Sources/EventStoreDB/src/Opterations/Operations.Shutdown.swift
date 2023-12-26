//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/12/12.
//

import Foundation
import GRPCSupport

@available(macOS 13.0, *)
extension OperationsClient {
    public struct Shutdown: UnaryUnary {
        public typealias Request = EmptyRequest
        public typealias Response = EmptyResponse
        
    }
}

