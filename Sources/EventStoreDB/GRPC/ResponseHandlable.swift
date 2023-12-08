//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/12/7.
//

import Foundation
import GRPC

public protocol ResponseHandlable{
    
}

public protocol UnaryResponseHandlable: ResponseHandlable where Self: GRPCCallable {
    func handle(response: Response.UnderlyingMessage) throws -> Response
}

@available(macOS 10.15, *)
public protocol StreamResponseHandlable: UnaryResponseHandlable where Self: GRPCCallable {
    func handle(responses: GRPCAsyncResponseStream<Response.UnderlyingMessage>) throws -> AsyncStream<Response>
}
