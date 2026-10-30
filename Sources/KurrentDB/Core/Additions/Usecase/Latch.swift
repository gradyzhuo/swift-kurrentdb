//
//  Latch.swift
//  KurrentCore
//

import Synchronization

/// A one-shot signal for a single waiter: the first `open()` or `fail(_:)` resolves the current
/// `wait()` and every later one; later `open()` / `fail(_:)` calls are no-ops. Two concurrent
/// `wait()` calls are not supported. A waiter whose task is cancelled fails the latch with
/// `CancellationError`.
///
/// A lazy read uses one to learn that the server accepted the call (open) or that the call failed
/// before that (fail), and the direct path a second one to park the RPC handler until the
/// consumer is done.
package final class Latch: Sendable {
    private enum State {
        case pending(CheckedContinuation<Void, any Error>?)
        case opened
        case failed(any Error)
    }

    private let state = Mutex(State.pending(nil))

    package init() {}

    package func open() { resolve(.success(())) }
    package func fail(_ error: any Error) { resolve(.failure(error)) }

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

    package func wait() async throws {
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
