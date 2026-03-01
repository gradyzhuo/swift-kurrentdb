//
//  GRPCClient+Additions.swift
//  KurrentCore
//
//  Created by Grady Zhuo on 2024/5/25.
//

import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import NIOCore
import NIOTransportServices

extension GRPCClient where Transport == HTTP2ClientTransport.Posix{
    package convenience init(from node: Node) throws {
        try self.init(transport: .http2NIOPosix(
            target: node.endpoint.target,
            transportSecurity: node.settings.transportSecurity
        ))
    }
}
