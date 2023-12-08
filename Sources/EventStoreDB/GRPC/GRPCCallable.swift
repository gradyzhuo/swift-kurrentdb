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


public protocol OptionBuildable {
    associatedtype Options: EventStoreOptions
    
    var options: Options { get }
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
