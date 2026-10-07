//
//  DeadlineCancellation.swift
//  KurrentCore
//

import GRPCCore
import Synchronization

/// Records that an RPC handler observed task cancellation.
///
/// grpc-swift enforces a call deadline by cancelling the handler. Newer releases then throw
/// `RPCError(.deadlineExceeded)` from the call; older ones (resolved under Swift 6.0) rethrow the
/// handler's own `CancellationError`, or return normally when the handler's loop just ended on
/// cancellation. The owner of the call cannot tell these apart from the call's result alone, so the
/// handler marks what it saw and the owner maps it with `deadlineOrOriginal(_:)`.
package final class HandlerCancellation: Sendable {
    private let observed = Mutex(false)

    package init() {}

    package func mark() { observed.withLock { $0 = true } }
    package var isMarked: Bool { observed.withLock { $0 } }
}

/// Maps a `CancellationError` that the owner's task did not request to the deadline error.
///
/// Our own `close()` cancels the owner's task, so `Task.isCancelled` is true for a requested
/// cancellation; a `CancellationError` seen while the task is not cancelled was
/// raised either by grpc-swift enforcing the call deadline, or by the consumer cancelling the hand-off; the latter is harmless because the hand-off is already terminal, so `finish(throwing:)` is a no-op and the mapped error is dropped. Must be called from the owner's task.
package func deadlineOrOriginal(_ error: any Error) -> any Error {
    guard !Task.isCancelled else { return error }
    if error is CancellationError {
        return deadlineExceededError()
    }
    // Unary calls under the older grpc-swift wrap the handler's cancellation:
    // RPCError(.unknown, "The transport threw an unexpected error.", cause: CancellationError()).
    if let rpcError = error as? RPCError, rpcError.cause is CancellationError {
        return deadlineExceededError()
    }
    return error
}

package func deadlineExceededError() -> RPCError {
    RPCError(code: .deadlineExceeded, message: "RPC timed out before completing")
}
