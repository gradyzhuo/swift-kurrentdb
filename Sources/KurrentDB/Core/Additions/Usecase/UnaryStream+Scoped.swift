//
//  UnaryStream+Scoped.swift
//  KurrentCore
//

import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix
import Synchronization

/// One-shot signal: the server accepted the call (open) or the call failed before that (fail).
private final class AcceptanceGate: Sendable {
    private enum State {
        case pending(CheckedContinuation<Void, any Error>?)
        case opened
        case failed(any Error)
    }

    private let state = Mutex(State.pending(nil))

    func open() {
        resolve(.success(()))
    }

    func fail(_ error: any Error) {
        resolve(.failure(error))
    }

    private func resolve(_ result: Result<Void, any Error>) {
        let waiter: CheckedContinuation<Void, any Error>? = state.withLock { state in
            guard case let .pending(waiter) = state else { return nil }
            switch result {
            case .success: state = .opened
            case let .failure(error): state = .failed(error)
            }
            return waiter
        }
        waiter?.resume(with: result)
    }

    func wait() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let immediate: Result<Void, any Error>? = state.withLock { state in
                    switch state {
                    case .pending:
                        state = .pending(continuation)
                        return nil
                    case .opened:
                        return .success(())
                    case let .failed(error):
                        return .failure(error)
                    }
                }
                if let immediate {
                    continuation.resume(with: immediate)
                }
            }
        } onCancel: {
            fail(CancellationError())
        }
    }
}

/// An accepted scoped RPC: the task running it, its hand-off and its shared-connection lease.
package final class ScopedCall<Response: Sendable>: Sendable {
    package let handoff: ResponseHandoff<Response>
    private let lease: SharedLease
    private let task: Task<Void, Never>

    fileprivate init(handoff: ResponseHandoff<Response>, lease: SharedLease, task: Task<Void, Never>) {
        self.handoff = handoff
        self.lease = lease
        self.task = task
    }

    /// Ends the RPC and returns the lease. Returns only after the RPC task has finished, so
    /// nothing of this call outlives it. Cancelling the task cancels only this RPC; the shared
    /// connection stays up for other calls.
    package func close() async {
        handoff.cancel()
        task.cancel()
        await task.value
        lease.release()
    }
}

/// Scoped delivery: the RPC lives exactly as long as the caller's `body`.
extension ScopedStreamResponse where Transport == HTTP2ClientTransport.Posix {
    /// Runs the call for the duration of `body`.
    ///
    /// A call the server rejects before accepting it (status-only response such as
    /// unauthenticated or access denied), or that fails to connect, is thrown here as
    /// `KurrentError` before `body` runs and is retried per the retry policy. Errors after the
    /// call was accepted, including stream-not-found, surface while `body` iterates, as with `read()`.
    ///
    /// If the caller's task is cancelled, this throws `CancellationError` (whether while waiting
    /// for the server to accept the call or after `body` started); `body` sees the stream end and
    /// its result is discarded, so a truncated result is never returned as success.
    package func performScoped<R>(
        selector: NodeSelector,
        callOptions: CallOptions,
        credentials: Authentication? = nil,
        isolation: isolated (any Actor)? = #isolation,
        body: (AsyncThrowingStream<Response, any Error>) async throws -> R
    ) async throws -> R {
        // Retry covers only establishing the call: once body has seen events, a retry would
        // hand them to it a second time.
        let call: ScopedCall<Response>
        do {
            call = try await withRetry(
                policy: selector.retryPolicy,
                selectNode: { try await selector.select() },
                invalidate: { await selector.invalidate() }
            ) { node in
                try await open(node: node, callOptions: callOptions, credentials: credentials)
            }
        } catch {
            // open maps a cancelled caller to connectionClosed; surface it as cancellation.
            if case .connectionClosed = error, Task.isCancelled { throw CancellationError() }
            throw error
        }

        let result: R
        do {
            result = try await body(call.handoff.makeStream())
        } catch {
            await call.close()
            throw error
        }
        await call.close()
        try Task.checkCancellation()
        return result
    }

    /// Starts the RPC on the shared connection and returns once the server accepted it.
    package func open(node: Node, callOptions: CallOptions, credentials: Authentication?) async throws(KurrentError) -> ScopedCall<Response> {
        guard node.serverInfo.isSupported(method: methodDescriptor) else {
            throw .unsupportedFeature(methodDescriptor)
        }

        let lease = try node.connections.acquire(node.endpoint)
        let request: ClientRequest<UnderlyingRequest>
        do {
            request = try withRethrowingError(usage: "\(Self.self).\(#function)") {
                try self.request(metadata: Metadata(from: node.settings, overriding: credentials))
            }
        } catch {
            lease.release()
            throw error
        }

        let handoff = ResponseHandoff<Response>()
        let accepted = AcceptanceGate()
        let task = Task {
            do {
                try await self.call(connection: lease.client, request: request, callOptions: callOptions) { response in
                    switch response.accepted {
                    case .success:
                        accepted.open()
                        // Same as the buffered send(): errors from the messages or from
                        // handle(message:) reach the consumer as they are.
                        do {
                            for try await message in response.messages {
                                try await handoff.send(self.handle(message: message))
                            }
                            handoff.finish()
                        } catch {
                            handoff.finish(throwing: error)
                        }
                    case let .failure(error):
                        accepted.fail(error)
                    }
                }
            } catch {
                // No-op for whichever side already resolved.
                accepted.fail(error)
                handoff.finish(throwing: error)
            }
        }

        let call = ScopedCall(handoff: handoff, lease: lease, task: task)
        do {
            try await withRethrowingError(usage: "\(Self.self).\(#function)") {
                try await accepted.wait()
            }
        } catch {
            await call.close()
            // A cancelled caller is not an internal failure; map it the way withRetry's backoff
            // does. connectionClosed is not a node failure, so it is never retried.
            if Task.isCancelled { throw .connectionClosed }
            throw error
        }
        return call
    }
}
