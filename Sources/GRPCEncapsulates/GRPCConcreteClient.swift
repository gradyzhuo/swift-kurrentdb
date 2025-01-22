//
//  GRPCConcreteService.swift
//
//
//  Created by Grady Zhuo on 2023/12/7.
//

import Foundation
import GRPCCore
import GRPCNIOTransportCore

public protocol GRPCConcreteService: Sendable {
    associatedtype Transport: ClientTransport
    associatedtype UnderlyingClient: UnderlyGRPCClient where UnderlyingClient.Transport == Transport
}
