//
//  GRPCConcreteService.swift
//
//
//  Created by Grady Zhuo on 2023/12/7.
//

import Foundation
import GRPCCore
import GRPCNIOTransportCore

public protocol ConcreteService: Sendable {
    associatedtype UnderlyingService
    associatedtype Client: GRPCServiceClient
}

