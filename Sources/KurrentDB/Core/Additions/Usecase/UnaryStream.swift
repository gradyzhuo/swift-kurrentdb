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

        // A stream response carries the connection out of this function (send() returns right
        // after spawning its Task), so each call gets its own connection. The completion closure
        // holds the connection so it (and the provider) stay alive until the stream terminates.
        // If send() finishes the continuation before returning, mark the usecase
        // BufferedStreamResponse instead and it will use the shared connection.
        let connection = try node.connections.openDedicated(for: node.endpoint)
        do {
            return try await withRethrowingError(usage: "\(Self.self).\(#function)") {
                let metadata = try Metadata(from: node.settings, overriding: credentials)
                let request = try request(metadata: metadata)
                let responses = try await send(connection: connection.client, request: request, callOptions: callOptions) { error in
                    if let error {
                        logger.error("The error is thrown in the response of UnaryStream: \(error)")
                    }
                    // cancel 這條連線的 runTask 會中止其上的 RPC,send() 裡跑 read 的內層 task
                    // 也因此結束。不能用 graceful shutdown:它會等無限期的訂閱結束。
                    connection.close()
                }
                // A shutdown closes the connection from outside; tell the response so a producer
                // suspended on a slow consumer is released instead of waiting for it.
                if let terminable = responses as? any ConnectionTerminable {
                    connection.onClose { terminable.connectionDidClose() }
                }
                return responses
            }
        } catch {
            // setup 失敗(metadata、request、呼叫本身):stream 永遠不會終止,由這裡收尾。
            // 成功時不可在這裡 close —— 那會立刻殺掉剛回傳出去的訂閱。
            connection.close()
            throw error
        }
    }
}
