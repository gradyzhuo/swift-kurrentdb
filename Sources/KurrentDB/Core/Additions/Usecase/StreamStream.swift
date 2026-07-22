//
//  StreamStream.swift
//  KurrentCore
//
//  Created by 卓俊諺 on 2025/1/20.
//

import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix

extension StreamStream where Transport == HTTP2ClientTransport.Posix {
    package func perform(selector: NodeSelector, callOptions: CallOptions, credentials: Authentication? = nil) async throws(KurrentError) -> Responses {
        try await withRetry(
            policy: selector.retryPolicy,
            selectNode: { try await selector.select() },
            invalidate: { await selector.invalidate() }
        ) { node in
            try await perform(node: node, callOptions: callOptions, credentials: credentials)
        }
    }

    package func perform(node: Node, callOptions: CallOptions, credentials: Authentication? = nil) async throws(KurrentError) -> Responses {
        guard node.serverInfo.isSupported(method: methodDescriptor) else {
            throw .unsupportedFeature(methodDescriptor)
        }
        
        let client = try GRPCClient<HTTP2ClientTransport.Posix>(from: node)
        Task {
            logger.debug("[\(Self.name)] Opening connection...")
            try await client.runConnections()
        }
        
        return try await withRethrowingError(usage: "\(Self.self).\(#function)") {
            let metadata = try Metadata(from: node.settings, overriding: credentials)
            return try await send(connection: client, metadata: metadata, callOptions: callOptions) { error in
                if let error {
                    logger.error("The error is thrown in the response of StreamStream: \(error)")
                }

                logger.debug("[\(Self.name)] Closing connection...")
                client.beginGracefulShutdown()
            }
        }
    }
}
