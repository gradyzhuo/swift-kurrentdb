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
    package convenience init(from node: Node) throws(KurrentError) {
        let transport: HTTP2ClientTransport.Posix = try withRethrowingError(usage: "\(Self.self).init(from: ClientSettings)") {
            try .http2NIOPosix(
                target: node.endpoint.target,
                transportSecurity: node.settings.transportSecurity
            )
        }
        self.init(transport: transport)
    }
}
