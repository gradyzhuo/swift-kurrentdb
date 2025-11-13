//
//  Usecase.swift
//  GRPCEncapsulates
//
//  Created by Grady Zhuo on 2023/10/29.
//

import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import SwiftProtobuf

package protocol Usecase {
    associatedtype ServiceClient: GRPCServiceClient where ServiceClient.Transport == Transport
    associatedtype Transport: ClientTransport where Transport == ServiceClient.Transport
    
    static var name: String { get }
}
