//
//  StreamUnary.swift
//  KurrentCore
//
//  Created by 卓俊諺 on 2025/1/20.
//

import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix

extension StreamUnary where Transport == HTTP2ClientTransport.Posix {
    package func send(connection: GRPCClient<Transport>, metadata: Metadata, callOptions: CallOptions) async throws -> Response {
        try await send(connection: connection, request: request(metadata: metadata), callOptions: callOptions)
    }

    package func perform(selector: NodeSelector, callOptions: CallOptions) async throws(KurrentError) -> Response {
        let node = try await selector.select()
        do throws(KurrentError) {
            return try await perform(node: node, callOptions: callOptions)
        } catch let error where error.isNodeFailure {
            await selector.invalidate()
            let retryNode = try await selector.select()
            return try await perform(node: retryNode, callOptions: callOptions)
        }
    }

    package func perform(node: Node, callOptions: CallOptions) async throws(KurrentError) -> Response {
        guard node.serverInfo.isSupported(method: methodDescriptor) else {
            throw .unsupportedFeature(methodDescriptor)
        }
        
        let client = try GRPCClient<HTTP2ClientTransport.Posix>(from: node)
        Task {
            logger.debug("[\(Self.name)] Opening connection...")
            try await client.runConnections()
        }
        
        defer{
            logger.debug("[\(Self.name)] Closing connection...")
            client.beginGracefulShutdown()
        }
        
        return try await withRethrowingError(usage: "\(Self.self).\(#function)") {
            let metadata = Metadata(from: node.settings)
            return try await send(connection: client, metadata: metadata, callOptions: callOptions)
        }
    }
}
