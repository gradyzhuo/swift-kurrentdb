//
//  GRPCCallable.swift
//
//
//  Created by Grady Zhuo on 2023/10/29.
//

import Foundation
import GRPCCore
import SwiftProtobuf

public protocol Usecase {
    associatedtype Transport: ClientTransport
    associatedtype Client: GRPCConcreteService where Client.Transport == Transport
}
