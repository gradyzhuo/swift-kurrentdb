//
//  ResponseHandlable.swift
//
//
//  Created by Grady Zhuo on 2023/12/7.
//

import Foundation
import GRPC

public protocol ResponseHandlable {}

public protocol UnaryResponseHandlable: ResponseHandlable where Self: GRPCCallable {
    func handle(response: Response.UnderlyingMessage) throws -> Response
}

extension UnaryResponseHandlable {
    @discardableResult
    public func handle(response: Response.UnderlyingMessage) throws -> Response {
        try .init(from: response)
    }
}

public protocol StreamResponseHandlable: UnaryResponseHandlable where Self: GRPCCallable {
    func handle(responses: GRPCAsyncResponseStream<Response.UnderlyingMessage>) throws -> Responses
}

extension StreamResponseHandlable {
    public typealias Responses = AsyncThrowingStream<Self.Response, Error>

    @discardableResult
    public func handle(responses: GRPCAsyncResponseStream<Response.UnderlyingMessage>) throws -> Responses {
        return .init {
            for try await message in responses {
                return try self.handle(response: message)
            }
            return nil
        }
    }
}
