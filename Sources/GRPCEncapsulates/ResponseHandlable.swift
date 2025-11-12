//
//  ResponseHandlable.swift
//  GRPCEncapsulates
//
//  Created by Grady Zhuo on 2023/12/7.
//

import Foundation
import GRPCCore
import SwiftProtobuf

package protocol ResponseHandlable: Sendable {
    associatedtype UnderlyingResponse: Message
    associatedtype Response: Sendable
}

package protocol UnaryResponseHandlable: ResponseHandlable where Self: Usecase {}

extension UnaryResponseHandlable where Response: GRPCResponse<UnderlyingResponse> {
    @discardableResult
    package func handle(message: Response.UnderlyingMessage) throws -> Response {
        try Response(from: message)
    }

    @discardableResult
    package func handle(response: ClientResponse<Response.UnderlyingMessage>) throws -> Response {
        try handle(message: response.message)
    }
}

package protocol StreamResponseHandlable: UnaryResponseHandlable where Self: Usecase {
    associatedtype Responses: Sendable
}
