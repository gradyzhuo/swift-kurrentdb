//
//  GRPCConcreteClient.swift
//
//
//  Created by Grady Zhuo on 2023/12/7.
//

import Foundation
import GRPCCore
import GRPCNIOTransportCore

public protocol GRPCConcreteClient: Sendable {
    associatedtype Transport: ClientTransport
    associatedtype UnderlyingClient: UnderlyGRPCClient where UnderlyingClient.Transport == Transport

//    var underlying: UnderlyingClient { get }
//    var metadata: Metadata { get }
//    var callOptions: CallOptions { set get }
    
//    init(wrapping client: GRPCClient<Transport>, metadata: Metadata, callOptions: CallOptions)
}
