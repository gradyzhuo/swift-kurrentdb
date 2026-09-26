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

        // stream 回應會把連線帶出這個函式(send() 裡 spawn Task 後就 return),所以每次呼叫
        // 獨立一條。completion 閉包持有 connection,讓它(以及 provider)活到 stream 終止為止。
        // 若 send() 在回傳前就 finish 了 continuation,改標 BufferedStreamResponse 走共用連線。
        let connection = try node.connections.openDedicated(for: node.endpoint)
        do {
            return try await withRethrowingError(usage: "\(Self.self).\(#function)") {
                let metadata = try Metadata(from: node.settings, overriding: credentials)
                let request = try request(metadata: metadata)
                return try await send(connection: connection.client, request: request, callOptions: callOptions) { error in
                    if let error {
                        logger.error("The error is thrown in the response of UnaryStream: \(error)")
                    }
                    // cancel 這條連線的 runTask 會中止其上的 RPC,send() 裡跑 read 的內層 task
                    // 也因此結束。不能用 graceful shutdown:它會等無限期的訂閱結束。
                    connection.close()
                }
            }
        } catch {
            // setup 失敗(metadata、request、呼叫本身):stream 永遠不會終止,由這裡收尾。
            // 成功時不可在這裡 close —— 那會立刻殺掉剛回傳出去的訂閱。
            connection.close()
            throw error
        }
    }
}
