//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/10/29.
//

import Foundation
import SwiftProtobuf
import GRPC

internal protocol _GRPCClient {
    associatedtype UnderlyingClient
    associatedtype UnderlyingRequest: Message
    associatedtype BingingResponse: GRPCBridge
    
    var underlyingClient: UnderlyingClient { get }
    
    init(underlyingClient: UnderlyingClient)
}

public protocol GRPCCallImplementable {
    associatedtype UnderlyingRequest: Message
    associatedtype BingingResponse: GRPCBridge
}



public protocol UnaryUnaryCall: GRPCCallImplementable {
    func call(request: UnderlyingRequest) async throws -> BingingResponse
}

@available(macOS 10.15, *)
public protocol UnaryStreamCall: GRPCCallImplementable {
    typealias Responses = AsyncStream<BingingResponse>
    
    func call(request: UnderlyingRequest) throws -> Responses
}

public protocol StreamUnaryCall: GRPCCallImplementable {
    typealias Requests = [UnderlyingRequest]
    
    func call(requests: Requests) async throws -> BingingResponse
}

@available(macOS 10.15, *)
public protocol StreamStreamCall: GRPCCallImplementable {
    typealias Requests = [UnderlyingRequest]
    typealias Responses = AsyncStream<BingingResponse>
    
    func call(requests: Requests) throws -> Responses
}
