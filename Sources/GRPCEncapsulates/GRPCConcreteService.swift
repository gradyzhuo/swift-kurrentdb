//
//  GRPCConcreteService.swift
//  GRPCEncapsulates
//
//  Created by Grady Zhuo on 2023/12/7.
//

import Foundation
import GRPCCore
import GRPCNIOTransportCore

package protocol GRPCConcreteService: Sendable {
    associatedtype Transport: ClientTransport
    associatedtype Client: GRPCServiceClient where Client.Transport == Transport
}
