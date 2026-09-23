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
        
        // stream 回應會把連線帶出這個函式,所以每次呼叫獨立一條。completion 閉包持有
        // connection,讓它(以及 provider)活到 stream 終止為止。
        let connection = try node.connections.openDedicated(for: node.endpoint)
        do {
            return try await withRethrowingError(usage: "\(Self.self).\(#function)") {
                let metadata = try Metadata(from: node.settings, overriding: credentials)
                return try await send(connection: connection.client, metadata: metadata, callOptions: callOptions) { error in
                    if let error {
                        logger.error("The error is thrown in the response of StreamStream: \(error)")
                    }
                    // graceful shutdown 會等待進行中的 RPC 完成 —— 對長生命週期訂閱而言
                    // 那可能永遠不會發生。取消執行 runConnections() 的 task 才會中止所有工作。
                    connection.close()
                }
            }
        } catch {
            // setup 失敗:stream 永遠不會終止,由這裡收尾。成功時不可在這裡 close。
            connection.close()
            throw error
        }
    }
}
