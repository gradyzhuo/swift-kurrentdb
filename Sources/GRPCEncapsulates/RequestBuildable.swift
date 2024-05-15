//
//  RequestBuildable.swift
//
//
//  Created by Grady Zhuo on 2023/12/7.
//

import Foundation

public protocol RequestBuildable {}

package protocol StreamRequestBuildable: RequestBuildable where Self: GRPCCallable {
    func build() throws -> [Request.UnderlyingMessage]
}

package protocol UnaryRequestBuildable: RequestBuildable where Self: GRPCCallable {
    func build() throws -> Request.UnderlyingMessage
}

extension UnaryRequestBuildable where Request == GenericGRPCRequest<EventStore_Client_Empty> {
    package func build() throws -> Request.UnderlyingMessage {
        .init()
    }
}
