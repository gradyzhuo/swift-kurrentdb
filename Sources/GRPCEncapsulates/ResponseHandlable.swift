//
//  ResponseHandlable.swift
//
//
//  Created by Grady Zhuo on 2023/12/7.
//

import Foundation
import SwiftProtobuf
import GRPCCore

public protocol ResponseHandlable: Sendable {
    associatedtype UnderlyingResponse: Message
    associatedtype Response
}

public protocol UnaryResponseHandlable: ResponseHandlable where Self: Usecase{
}

extension UnaryResponseHandlable where Response: GRPCResponse<UnderlyingResponse> {
    @discardableResult
    public func handle(message: Response.UnderlyingMessage) throws -> Response {
        return try Response.init(from: message)
    }
    
    @discardableResult
    public func handle(response: ClientResponse<Response.UnderlyingMessage>) throws -> Response {
        return try handle(message: response.message)
    }
}

public protocol StreamResponseHandlable: UnaryResponseHandlable where Self: Usecase {
    associatedtype Responses//: AsyncSequence, Sendable
//    func handle(messages: RPCAsyncSequence<Response.UnderlyingMessage, Error>) async throws -> Responses
}

extension StreamResponseHandlable where Responses == RPCAsyncSequence<Response, Error>{
//    @discardableResult
//    public func handle(messages: RPCAsyncSequence<Response.UnderlyingMessage, Error>) throws -> Responses {
////        let responses = messages.compactMap { message -> Responses.Element in
////            return try self.handle(message: message)
////        }
//        
//        let stream = AsyncThrowingStream<Response, Error>.init {
//            var iterator = messages.makeAsyncIterator()
//            guard let message = try await iterator.next() else {
//                return nil
//            }
//            return try handle(message: message)
//        }
//        
////        let stream =  AsyncThrowingStream<Response, Error>.init { continuation in
////            Task.detached{
////                for try await message in messages {
////                    continuation.yield(try handle(message: message))
////                }
////                continuation.finish()
////            }
////        }
//        return .init(wrapping: stream)
//    }
    
//    @discardableResult
//    public func handle(response: StreamingClientResponse<Response.UnderlyingMessage>) async throws -> Responses {
//        return try await handle(messages: response.messages)
//    }
}
