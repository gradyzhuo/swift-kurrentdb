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
        let connectionTask = Task {
            logger.debug("[\(Self.name)] Opening connection...")
            do {
                try await client.runConnections()
            } catch is CancellationError {
                // teardown 會取消本 task,這是正常收尾,不記錄為錯誤。
                // (特性化測試顯示取消時 runConnections() 多半正常返回而不拋錯,
                //  此分支僅為防禦不同 grpc 版本/transport 的行為差異。)
            } catch {
                // 其餘錯誤 —— 例如 transport 建立失敗 —— 過去被這個無主 task 靜默吞掉,
                // 使連線故障無從診斷。至少記錄下來。
                logger.error("[\(Self.name)] Connection run loop terminated with error: \(error)")
            }
        }

        return try await withRethrowingError(usage: "\(Self.self).\(#function)") {
            let metadata = try Metadata(from: node.settings, overriding: credentials)
            return try await send(connection: client, metadata: metadata, callOptions: callOptions) { error in
                if let error {
                    logger.error("The error is thrown in the response of StreamStream: \(error)")
                }

                logger.debug("[\(Self.name)] Closing connection...")
                // graceful shutdown 會等待進行中的 RPC 完成 —— 對長生命週期訂閱而言
                // 那可能永遠不會發生。依 GRPCClient.runConnections() 的文件,
                // 取消執行該方法的 Task 是中止所有工作的正規手段。
                client.beginGracefulShutdown()
                connectionTask.cancel()
            }
        }
    }
}
