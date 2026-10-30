//
//  UnaryStream+Parked.swift
//  KurrentCore
//
//  The direct delivery path of a lazy read (§5.7): grpc-swift exposes the response stream only
//  inside the handler closure of `call(...)`, and closes it when the closure returns. Instead of
//  forwarding every message through `ResponseHandoff` from the handler's task, the handler hands
//  the response sequence (which is `Sendable`; only its iterator is not) to the consumer and parks
//  on a latch until the consumer is done, so the consumer pulls messages straight from the
//  transport with no task hand-off per element.
//

import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix
import Synchronization

/// What a parked RPC's handler task, its consumer and its shutdown handler share. The shutdown
/// handler captures this, never the `ParkedCall`, which the registry would then keep alive.
private final class ParkedRPC<Message: Sendable>: Sendable {
    /// Opened when the server accepted the call; failed when the call ended before that.
    let accepted = Latch()
    /// The handler parks on it after acceptance; opened when the consumer is done.
    let done = Latch()
    private let terminal = Mutex<(any Error)?>(nil)
    private let stash = Mutex<RPCAsyncSequence<Message, any Error>?>(nil)

    /// The first error recorded: the RPC's own (deadline, transport), or `connectionClosed` from
    /// `shutdown()`. Later errors never replace it, so a teardown error after a shutdown (the
    /// connection's run task being cancelled) cannot hide `connectionClosed`.
    var terminalError: (any Error)? {
        terminal.withLock { $0 }
    }

    func record(_ error: any Error) {
        terminal.withLock { slot in
            if slot == nil { slot = error }
        }
    }

    var messages: RPCAsyncSequence<Message, any Error>? {
        stash.withLock { $0 }
    }

    func hand(_ messages: RPCAsyncSequence<Message, any Error>) {
        stash.withLock { $0 = messages }
    }

    /// The shutdown handler: registered before the RPC task exists, so it cannot cancel it. It
    /// records the error, ends a wait for acceptance (whose failure branch then cancels the task)
    /// and releases a parked handler, which then throws `error` and so ends the RPC; the consumer
    /// sees the recorded error at its next element.
    func end(with error: KurrentError) {
        record(error)
        accepted.fail(error)
        done.fail(error)
    }
}

/// An accepted server-streaming RPC whose handler is parked on a latch: the consumer owns the
/// iteration of `messages`; `finish()` releases the handler and reports the RPC's own terminal
/// error. Owned by a lazy read iterator on its direct path.
package final class ParkedCall<Message: Sendable, Response: Sendable>: Sendable {
    package let messages: RPCAsyncSequence<Message, any Error>
    package let map: @Sendable (Message) throws -> Response?
    private let rpc: ParkedRPC<Message>
    private let lease: SharedLease
    private let task: Task<Void, Never>
    private let connections: ConnectionProvider
    private let shutdownHandlerID: ConnectionProvider.ShutdownHandlerID
    private let usage: String

    fileprivate init(
        messages: RPCAsyncSequence<Message, any Error>,
        map: @escaping @Sendable (Message) throws -> Response?,
        rpc: ParkedRPC<Message>,
        lease: SharedLease,
        task: Task<Void, Never>,
        connections: ConnectionProvider,
        shutdownHandlerID: ConnectionProvider.ShutdownHandlerID,
        usage: String
    ) {
        self.messages = messages
        self.map = map
        self.rpc = rpc
        self.lease = lease
        self.task = task
        self.connections = connections
        self.shutdownHandlerID = shutdownHandlerID
        self.usage = usage
    }

    /// Set by the handler task when `call(...)` ended with an error, and by `end(with:)`; checked per
    /// element, so the consumer does not drain messages that arrived before the RPC was cut off.
    /// Already a `KurrentError` (or `CancellationError`).
    package var terminalError: (any Error)? {
        rpc.terminalError
    }

    /// Lets the handler return, waits for the RPC to end, returns the lease, and reports the RPC's
    /// terminal error (nil when it ended cleanly). The shutdown handler is removed first: the
    /// consumer is done, so a shutdown from here on concerns no element of this read.
    package func finish() async -> (any Error)? {
        connections.removeShutdownHandler(shutdownHandlerID)
        rpc.done.open()
        await task.value
        lease.release()
        return rpc.terminalError
    }

    /// Ends the RPC now (cancels its task) and returns the lease once the task has finished.
    /// Cancelling the task cancels only this RPC; the read connection stays up for other calls.
    package func close() async {
        connections.removeShutdownHandler(shutdownHandlerID)
        rpc.done.open()
        task.cancel()
        await task.value
        lease.release()
    }

    /// `close()` for contexts that cannot await (an iterator's `deinit`): the shutdown handler is
    /// removed at once, the lease once the RPC task has finished, from an unstructured task.
    package func closeInBackground() {
        connections.removeShutdownHandler(shutdownHandlerID)
        rpc.done.open()
        task.cancel()
        let task = self.task
        let lease = self.lease
        Task {
            await task.value
            lease.release()
        }
    }

    /// Ends the call with `error` as `shutdown()` does: records it (unless an error is already
    /// recorded) and releases the parked handler.
    package func end(with error: KurrentError) {
        rpc.end(with: error)
    }

    /// An error the consumer's iteration of `messages` (or `map`) threw, as the consumer receives it.
    package func mapFailure(_ error: any Error) -> any Error {
        mapStreamError(error, usage: usage)
    }
}

extension ScopedStreamResponse where Transport == AnyClientTransport {
    /// Like `open(node:callOptions:credentials:)` — the same `.read` connection, acceptance gate,
    /// shutdown registration and error mapping — but after the server accepted the call its
    /// handler parks, and the consumer iterates the response sequence itself.
    package func openParked(node: Node, callOptions: CallOptions, credentials: Authentication?) async throws(KurrentError) -> ParkedCall<UnderlyingResponse, Response> {
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

        let rpc = ParkedRPC<UnderlyingResponse>()
        // Registered before the RPC starts, as open() does, so a shutdown at any later point reaches
        // this call as connectionClosed (see ParkedRPC.end(with:)). Runs at once if the provider is
        // already shut down.
        let connections = node.connections
        let shutdownHandlerID = connections.registerShutdownHandler {
            rpc.end(with: .connectionClosed)
        }
        let usage = "\(Self.name)"
        let handlerCancellation = HandlerCancellation()
        let task = Task {
            do {
                try await self.call(connection: lease.client, request: request, callOptions: callOptions) { response in
                    switch response.accepted {
                    case .success:
                        // Park until the consumer is done (done opens), or until this task is
                        // cancelled (close(), or grpc-swift enforcing the deadline), or until
                        // shutdown() fails the latch.
                        rpc.hand(response.messages)
                        rpc.accepted.open()
                        do {
                            try await rpc.done.wait()
                        } catch is CancellationError {
                            handlerCancellation.mark()
                            throw CancellationError()
                        }
                    case let .failure(error):
                        // Rethrown for the catch below to map on this task, as open() does: a call
                        // timeout that expired before acceptance becomes deadlineExceeded.
                        throw error
                    }
                }
                // Older grpc-swift returns normally when the deadline cancelled the handler; this
                // task itself was not cancelled, so that is the deadline, not a clean end.
                if handlerCancellation.isMarked, !Task.isCancelled { throw deadlineExceededError() }
            } catch {
                // Older grpc-swift rethrows the handler's CancellationError instead of the deadline
                // error; map it unless this task was cancelled on purpose (close()).
                let error = mapStreamError(deadlineOrOriginal(error), usage: usage)
                rpc.record(error)
                rpc.accepted.fail(error)   // no-op once accepted
            }
        }

        let messages: RPCAsyncSequence<UnderlyingResponse, any Error>
        do throws(KurrentError) {
            try await withRethrowingError(usage: "\(Self.self).\(#function)") {
                try await rpc.accepted.wait()
            }
            // Always there: the handler stores the sequence before it opens the gate.
            guard let handed = rpc.messages else {
                throw .internalClientError(reason: "`\(usage)` was accepted without a response stream.")
            }
            messages = handed
        } catch {
            connections.removeShutdownHandler(shutdownHandlerID)
            rpc.done.open()
            task.cancel()
            await task.value
            lease.release()
            // A cancelled caller is not an internal failure; map it the way withRetry's backoff
            // does, so it is not retried.
            if Task.isCancelled { throw .connectionClosed }
            throw error
        }
        return ParkedCall(
            messages: messages,
            map: { try self.scopedResponse(for: $0) },
            rpc: rpc,
            lease: lease,
            task: task,
            connections: connections,
            shutdownHandlerID: shutdownHandlerID,
            usage: usage
        )
    }
}
