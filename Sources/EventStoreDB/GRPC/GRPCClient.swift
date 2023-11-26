//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/10/29.
//

import Foundation
import SwiftProtobuf
import GRPC

public protocol GRPCCallable {
    
    associatedtype Request: GRPCRequest
    associatedtype Response: GRPCResponse
    
}

//public protocol UnaryUnary: GRPCCallable, UnaryRequest, UnaryResponse where Self.UnderlyingResponse == Self.BindingResponse.UnderlyingResponse{
//    typealias Outcome = BindingResponse
//}

//@available(macOS 10.15, *)
//public protocol UnaryStream: GRPCCallable, UnaryRequest, StreamResponse where Self.BindingResponse.UnderlyingResponse == Self.UnderlyingResponse{
//    
//    typealias Outcome = AsyncStream<BindingResponse>
//}
//
//public protocol StreamUnary: GRPCCallable, StreamRequest, UnaryResponse where Self.UnderlyingResponse == Self.BindingResponse.UnderlyingResponse {
//    typealias Outcome = BindingResponse
//}
//
//@available(macOS 10.15, *)
//public protocol StreamStream: GRPCCallable, StreamRequest, StreamResponse {
//    typealias Outcome = AsyncStream<BindingResponse>
//}

public protocol OptionBuildable {
    associatedtype Options: EventStoreOptions
    
    var options: Options { get }
}

public protocol RequestBuildable {
    
    
}

public protocol StreamRequestBuildable: RequestBuildable where Self: GRPCCallable{
    func build() throws -> [Request.UnderlyingMessage]
}

public protocol UnaryRequestBuildable: RequestBuildable where Self: GRPCCallable{
    func build() throws -> Request.UnderlyingMessage
}

public protocol ResponseHandlable{
    
}

public protocol UnaryResponseHandlable: ResponseHandlable where Self: GRPCCallable {
    func handle(response: Response.UnderlyingMessage) throws -> Response
}

@available(macOS 10.15, *)
public protocol StreamResponseHandlable: UnaryResponseHandlable where Self: GRPCCallable {
    func handle(responses: GRPCAsyncResponseStream<Response.UnderlyingMessage>) throws -> AsyncStream<Response>
}


public protocol UnaryUnary: GRPCCallable, UnaryRequestBuildable, UnaryResponseHandlable{
}


@available(macOS 10.15, *)
public protocol UnaryStream: GRPCCallable, UnaryRequestBuildable, StreamResponseHandlable{
    
}

public protocol StreamUnary: GRPCCallable, StreamRequestBuildable, UnaryResponseHandlable{
}

@available(macOS 10.15, *)
public protocol StreamStream: GRPCCallable, StreamRequestBuildable, StreamResponseHandlable{
    
}

@available(macOS 10.15, *)
extension UnaryResponseHandlable{
    
    @discardableResult
    public func handle(response: Response.UnderlyingMessage) throws -> Response{
        return try .init(from: response)
    }
    
}

@available(macOS 10.15, *)
extension StreamResponseHandlable{
    public typealias Responses = AsyncStream<Response>
    
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

//@available(macOS 10.15, *)
//extension GRPCCallable where Self: StreamStream, Self: UnaryStream{
//    
//    public func handle<T>(underlying responses: GRPCAsyncResponseStream<T>) throws -> AsyncStream<BindingResponse.Element> where T == BindingResponse.Element.UnderlyingMessage{
//        
//        return try BindingResponse.build(underlying: responses)
//    }
//    
//}

//protocol UnaryUnaryCall: UnaryUnary {
//    func call(request: UnderlyingRequest) async throws -> BindingResponse
//}
//
//@available(macOS 10.15, *)
//protocol UnaryStreamCall: UnaryStream {
//    func call(request: UnderlyingRequest) throws -> Responses
//}
//
//protocol StreamUnaryCall: StreamUnary {
//    func call(requests: Requests) async throws -> BindingResponse
//}
//
//@available(macOS 10.15, *)
//protocol StreamStreamCall: StreamStream{
//    func call(requests: Requests) throws -> Responses
//}
