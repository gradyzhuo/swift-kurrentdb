//
//  StreamStream.swift
//  KurrentCore
//
//  Created by 卓俊諺 on 2025/1/20.
//

import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix

extension StreamStream where Transport == AnyClientTransport {
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
        
        // The streamed response carries the connection out of this function, so every call gets its
        // own. The completion closure holds the connection, keeping it (and the provider) alive until the stream ends.
        let connection = try node.connections.openDedicated(for: node.endpoint)
        do {
            return try await withRethrowingError(usage: "\(Self.self).\(#function)") {
                let metadata = try Metadata(from: node.settings, overriding: credentials)
                return try await send(connection: connection.client, metadata: metadata, callOptions: callOptions) { error in
                    if let error {
                        logger.error("The error is thrown in the response of StreamStream: \(error)")
                    }
                    // A graceful shutdown waits for the RPCs in progress, which a long-lived subscription
                    // may never finish. Cancelling the task that runs runConnections() is what stops the work.
                    connection.close()
                }
            }
        } catch {
            // Setup failed: the stream will never end, so close here. Do not close here on success.
            connection.close()
            throw error
        }
    }
}
