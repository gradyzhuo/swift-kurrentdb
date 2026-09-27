//
//  UnaryStream+BufferedStreamResponse.swift
//  KurrentCore
//

import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix
import Synchronization

/// The completion closure is @Sendable and escaping, so it cannot capture a ~Copyable Mutex
/// directly; wrap it in a class.
private final class CompletionFlag: Sendable {
    private let fired = Mutex(false)
    func set() { fired.withLock { $0 = true } }
    var isSet: Bool { fired.withLock { $0 } }
}

/// UnaryStream usecases whose `send()` finishes the stream before returning (see
/// ``BufferedStreamResponse``): the RPC always ends inside `perform(node:)`, so they use the
/// shared connection exactly like `StreamUnary`.
///
/// Both `perform`s must be provided here. The call to `perform(node:)` inside
/// `perform(selector:)` is bound statically in generic context, so overriding only
/// `perform(node:)` would leave the base extension's `perform(selector:)` calling the
/// dedicated-connection version.
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

        // The response is consumed inside send() and the connection never leaves this function:
        // use the shared connection and return the lease on the way out.
        let lease = try node.connections.acquire(node.endpoint)
        defer { lease.release() }

        let completed = CompletionFlag()
        let responses = try await withRethrowingError(usage: "\(Self.self).\(#function)") {
            let metadata = try Metadata(from: node.settings, overriding: credentials)
            let request = try request(metadata: metadata)
            return try await send(connection: lease.client, request: request, callOptions: callOptions) { error in
                // Log only. Never touch lease.client: shutting down the shared GRPCClient
                // would fail every later call on this endpoint.
                completed.set()
                if let error {
                    logger.error("The error is thrown in the response of \(Self.name): \(error)")
                }
            }
        }

        // By the time send() returns the continuation must already be finished (onTermination
        // fires synchronously). If it is not, this usecase carried the stream out and must not
        // be marked BufferedStreamResponse.
        assert(completed.isSet, "\(Self.name) returned an open stream; it must conform to UnaryStream without BufferedStreamResponse (dedicated connection)")
        if !completed.isSet {
            logger.error("\(Self.name) is marked BufferedStreamResponse but returned an open stream; its lease is already released")
        }
        return responses
    }
}
