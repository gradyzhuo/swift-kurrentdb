//
//  RequestBuildable.swift
//  GRPCEncapsulates
//
//  Created by Grady Zhuo on 2023/12/7.
//

import Foundation
import Generated
import GRPCCore
import SwiftProtobuf

package protocol RequestBuildable {
    associatedtype UnderlyingRequest: Message
}

package protocol StreamRequestBuildable: RequestBuildable {
    func requestMessages() throws -> [UnderlyingRequest]
}

extension StreamRequestBuildable {
    package func request(metadata: Metadata) throws -> StreamingClientRequest<UnderlyingRequest> {
        let messages = try requestMessages()
        return StreamingClientRequest(metadata: metadata) { writer in
            try await writer.write(contentsOf: messages)
        }
    }
}

package protocol UnaryRequestBuildable: RequestBuildable {
    func requestMessage() throws -> UnderlyingRequest
}

extension UnaryRequestBuildable {
    package func request(metadata: Metadata) throws -> ClientRequest<UnderlyingRequest> {
        let message = try requestMessage()
        return .init(message: message, metadata: metadata)
    }
}

extension UnaryRequestBuildable where UnderlyingRequest == EventStore_Client_Empty {
    package func requestMessage() throws -> UnderlyingRequest {
        .init()
    }
}
