//
//  ResponseHandlable.swift
//
//
//  Created by Grady Zhuo on 2023/12/7.
//

import Foundation
@preconcurrency import GRPC

public protocol ResponseHandlable: Sendable {}

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
    func handle(responses: GRPCAsyncResponseStream<Response.UnderlyingMessage>, channel: GRPCChannel) throws -> Responses
}

extension StreamResponseHandlable {
    public typealias Responses = AsyncThrowingStream<Response, Error>

    @discardableResult
    public func handle(responses: GRPCAsyncResponseStream<Response.UnderlyingMessage>, channel: GRPCChannel) throws -> Responses {
        let iterator = responses.makeAsyncIterator()
        return .init {
            var iterator = iterator
            guard let message = try await iterator.next() else {
                try await channel.close().get()
                return nil
            }
            return try self.handle(response: message)
        }
    }
}
