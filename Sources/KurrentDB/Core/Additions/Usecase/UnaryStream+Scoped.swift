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

    func open() { resolve(.success(())) }
    func fail(_ error: any Error) { resolve(.failure(error)) }

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
                if let immediate { continuation.resume(with: immediate) }
            }
        } onCancel: {
            fail(CancellationError())
        }
    }
}

/// An accepted server-streaming RPC: the task running it, its hand-off, its shared-connection
/// lease and its shutdown handler. Owned by a lazy read iterator.
package final class ScopedCall<Response: Sendable>: Sendable {
    package let handoff: ResponseHandoff<Response>
    private let lease: SharedLease
    private let task: Task<Void, Never>
    private let connections: ConnectionProvider
    private let shutdownHandlerID: ConnectionProvider.ShutdownHandlerID

    fileprivate init(
        handoff: ResponseHandoff<Response>,
        lease: SharedLease,
        task: Task<Void, Never>,
        connections: ConnectionProvider,
        shutdownHandlerID: ConnectionProvider.ShutdownHandlerID
    ) {
        self.handoff = handoff
        self.lease = lease
        self.task = task
        self.connections = connections
        self.shutdownHandlerID = shutdownHandlerID
    }

    /// Ends the RPC and returns the lease, returning only after the RPC task has finished.
    /// Cancelling the task cancels only this RPC; the shared connection stays up for other calls.
    /// The order matters: cancelling the hand-off first makes the producer's exit quiet.
    package func close() async {
        connections.removeShutdownHandler(shutdownHandlerID)
        handoff.cancel()
        task.cancel()
        await task.value
        lease.release()
    }

    /// `close()` for contexts that cannot await (an iterator's `deinit`): the shutdown handler is
    /// removed at once, the lease once the RPC task has finished, from an unstructured task.
    package func closeInBackground() {
        connections.removeShutdownHandler(shutdownHandlerID)
        handoff.cancel()
        task.cancel()
        let task = self.task
        let lease = self.lease
        Task {
            await task.value
            lease.release()
        }
    }
}

extension ScopedStreamResponse where Transport == AnyClientTransport {
    /// Starts the RPC on the endpoint's shared `.read` connection and returns once the server accepted it.
    ///
    /// A call the server rejects before accepting it (status-only response) or that fails to
    /// connect throws here, as `KurrentError`, with the lease already returned; `withRetry`
    /// callers may retry node failures because no element has been delivered yet. A caller
    /// cancelled while waiting gets `KurrentError.connectionClosed` (typed throws); the lazy
    /// iterator maps that to `CancellationError`.
    ///
    /// The provider's `shutdown()` ends the call with `KurrentError.connectionClosed`, whether it is
    /// still waiting for acceptance (thrown here, not retried) or being iterated (thrown by the
    /// hand-off's next `next()`), through a shutdown handler registered before the wait.
    package func open(node: Node, callOptions: CallOptions, credentials: Authentication?) async throws(KurrentError) -> ScopedCall<Response> {
        guard node.serverInfo.isSupported(method: methodDescriptor) else {
            throw .unsupportedFeature(methodDescriptor)
        }

        let lease = try node.connections.acquire(node.endpoint, purpose: .read)
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
        // Registered before the RPC starts, so a shutdown at any later point reaches this call as
        // connectionClosed and never as the transport error its run task's cancellation causes
        // (a node failure to withRetry). Runs at once if the provider is already shut down. It
        // captures only the hand-off and the gate: never handoff.cancel(), which would end the
        // consumer with nil (a silently truncated read), and never the call, which the registry
        // would then keep alive.
        let connections = node.connections
        let shutdownHandlerID = connections.registerShutdownHandler {
            handoff.finish(throwing: KurrentError.connectionClosed)
            accepted.fail(KurrentError.connectionClosed)
        }
        let handlerCancellation = HandlerCancellation()
        let task = Task {
            do {
                try await self.call(connection: lease.client, request: request, callOptions: callOptions) { response in
                    switch response.accepted {
                    case .success:
                        accepted.open()
                        // An error from the messages, from handle(message:) or from send() propagates
                        // to the catch below, so whatever call(...) finally throws (the RPC's own
                        // error, e.g. deadlineExceeded, when grpc-swift cancels this task to enforce
                        // a deadline) is the terminal error.
                        do {
                            for try await message in response.messages {
                                if let response = try self.scopedResponse(for: message) {
                                    try await handoff.send(response)
                                }
                            }
                        } catch is CancellationError {
                            handlerCancellation.mark()
                            throw CancellationError()
                        }
                        if Task.isCancelled { handlerCancellation.mark() }
                    case let .failure(error):
                        accepted.fail(error)
                    }
                }
                // Older grpc-swift returns normally when the deadline cancelled the handler; this
                // task itself was not cancelled, so that is the deadline, not a clean end.
                if handlerCancellation.isMarked, !Task.isCancelled { throw deadlineExceededError() }
                // Finish only after the RPC returned, so a deadline that ends the loop above quietly
                // still surfaces as call(...)'s error. No-op when already finished.
                handoff.finish()
            } catch {
                // Older grpc-swift rethrows the handler's CancellationError instead of the deadline
                // error; map it unless this task was cancelled on purpose (close()).
                let error = mapStreamError(deadlineOrOriginal(error), usage: "\(Self.name)")
                // No-op for whichever side already resolved.
                accepted.fail(error)
                handoff.finish(throwing: error)
            }
        }

        let call = ScopedCall(handoff: handoff, lease: lease, task: task, connections: connections, shutdownHandlerID: shutdownHandlerID)
        do {
            try await withRethrowingError(usage: "\(Self.self).\(#function)") {
                try await accepted.wait()
            }
        } catch {
            await call.close()   // also removes the shutdown handler
            // A cancelled caller is not an internal failure; map it the way withRetry's backoff
            // does, so it is not retried.
            if Task.isCancelled { throw .connectionClosed }
            throw error
        }
        return call
    }
}
