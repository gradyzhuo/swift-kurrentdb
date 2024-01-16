//
//  GRPCCallable.swift
//
//
//  Created by Grady Zhuo on 2023/10/29.
//

import Foundation
import GRPC
import SwiftProtobuf

public protocol GRPCCallable {
    associatedtype Request: GRPCRequest
    associatedtype Response: GRPCResponse
}

public protocol UnaryUnary: GRPCCallable, UnaryRequestBuildable, UnaryResponseHandlable {}

public protocol UnaryStream: GRPCCallable, UnaryRequestBuildable, StreamResponseHandlable {}

public protocol StreamUnary: GRPCCallable, StreamRequestBuildable, UnaryResponseHandlable {}

public protocol StreamStream: GRPCCallable, StreamRequestBuildable, StreamResponseHandlable {}
