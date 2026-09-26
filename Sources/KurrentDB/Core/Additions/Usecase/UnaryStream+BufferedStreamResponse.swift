//
//  UnaryStream+BufferedStreamResponse.swift
//  KurrentCore
//

import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix
import Synchronization

/// completion closure 是 @Sendable escaping,不能直接捕獲 ~Copyable 的 Mutex,所以包一層。
private final class CompletionFlag: Sendable {
    private let fired = Mutex(false)
    func set() { fired.withLock { $0 = true } }
    var isSet: Bool { fired.withLock { $0 } }
}

/// `send()` 在回傳前就把 stream 收尾的 UnaryStream(見 ``BufferedStreamResponse``):
/// RPC 一定在 `perform(node:)` 內結束,所以跟 `StreamUnary` 一樣走共用連線。
///
/// 兩個 perform 都要在這裡提供 —— `perform(selector:)` 內對 `perform(node:)` 的呼叫是
/// 在 generic context 靜態綁定的,若只覆寫 `perform(node:)`,base extension 的
/// `perform(selector:)` 仍會叫到獨立連線那一版。
extension UnaryStream where Transport == HTTP2ClientTransport.Posix, Self: BufferedStreamResponse {
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

        // 回應在 send() 內就消費完,連線不會逃出這個函式:走共用連線,離開時還 lease。
        let lease = try node.connections.acquire(node.endpoint)
        defer { lease.release() }

        let completed = CompletionFlag()
        let responses = try await withRethrowingError(usage: "\(Self.self).\(#function)") {
            let metadata = try Metadata(from: node.settings, overriding: credentials)
            let request = try request(metadata: metadata)
            return try await send(connection: lease.client, request: request, callOptions: callOptions) { error in
                // 只能 log。絕對不可碰 lease.client:對共用的 GRPCClient 做 shutdown
                // 會讓同一 endpoint 之後所有呼叫都失敗。
                completed.set()
                if let error {
                    logger.error("The error is thrown in the response of \(Self.name): \(error)")
                }
            }
        }

        // send() 回傳時 continuation 必須已經 finish(onTermination 同步觸發)。沒有就是
        // 這個 usecase 把 stream 帶出去了,不該標 BufferedStreamResponse。
        assert(completed.isSet, "\(Self.name) returned an open stream; it must conform to UnaryStream without BufferedStreamResponse (dedicated connection)")
        if !completed.isSet {
            logger.error("\(Self.name) is marked BufferedStreamResponse but returned an open stream; its lease is already released")
        }
        return responses
    }
}
