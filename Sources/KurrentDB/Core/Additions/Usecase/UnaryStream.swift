//
//  UnaryStream.swift
//  KurrentCore
//
//  Created by 卓俊諺 on 2025/1/20.
//

import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix

extension UnaryStream where Transport == HTTP2ClientTransport.Posix {
    package func perform(selector: NodeSelector, callOptions: CallOptions) async throws(KurrentError) -> Responses{
        let node = try await selector.select()
        return try await perform(node: node, callOptions: callOptions)
    }
    
    package func perform(node: Node, callOptions: CallOptions) async throws(KurrentError) -> Responses{
        return try await withRethrowingError(usage: "\(Self.self).\(#function)") {
            let client = try GRPCClient<HTTP2ClientTransport.Posix>(from: node)
            Task.detached {
                logger.debug("[\(Self.name)] Opening connection...")
                try await client.runConnections()
            }
            
            let metadata = Metadata(from: node.settings)
            let request = try request(metadata: metadata)
            return try await send(connection: client, request: request, callOptions: callOptions) {
                if let error = $0 {
                    logger.error("The error is thrown in the response of UnaryStream: \(error)")
                }
                client.beginGracefulShutdown()
            }
        }
    }
}
