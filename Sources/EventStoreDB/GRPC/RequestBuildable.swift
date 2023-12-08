//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/12/7.
//

import Foundation

public protocol RequestBuildable {
    
    
}

public protocol StreamRequestBuildable: RequestBuildable where Self: GRPCCallable{
    func build() throws -> [Request.UnderlyingMessage]
}

public protocol UnaryRequestBuildable: RequestBuildable where Self: GRPCCallable{
    func build() throws -> Request.UnderlyingMessage
}
