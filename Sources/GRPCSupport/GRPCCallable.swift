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
