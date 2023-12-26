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


@available(macOS 13.0, *)
extension UnaryResponseHandlable{
    
    @discardableResult
    public func handle(response: Response.UnderlyingMessage) throws -> Response{
        return try .init(from: response)
    }
    
}


@available(macOS 13.0, *)
public protocol StreamResponseHandlable: UnaryResponseHandlable where Self: GRPCCallable {
    func handle(responses: GRPCAsyncResponseStream<Response.UnderlyingMessage>) throws -> AsyncStream<Response>
}

@available(macOS 13.0, *)
extension StreamResponseHandlable{
    public typealias Responses = AsyncStream<Self.Response>
    
    @discardableResult
    public func handle(responses: GRPCAsyncResponseStream<Response.UnderlyingMessage>) throws -> Responses {
        return .init { continuation in
            Task {
                for try await message in responses {
                    let response = try self.handle(response: message)
                    continuation.yield(response)
                }
                continuation.finish()
            }
        }
    }
}
