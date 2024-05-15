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

package protocol UnaryUnary: GRPCCallable, UnaryRequestBuildable, UnaryResponseHandlable {}

package protocol UnaryStream: GRPCCallable, UnaryRequestBuildable, StreamResponseHandlable {}

package protocol StreamUnary: GRPCCallable, StreamRequestBuildable, UnaryResponseHandlable {}

package protocol StreamStream: GRPCCallable, StreamRequestBuildable, StreamResponseHandlable {}
