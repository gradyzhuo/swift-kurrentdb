//
//  EstablishmentBudget.swift
//  KurrentCore
//

/// What finished first in `withEstablishmentBudget`.
private enum EstablishmentOutcome<T: Sendable>: Sendable {
    case opened(T)
    case expired
    /// The timer was cancelled: the operation finished first, or the caller was cancelled.
    case timerCancelled
}

/// Runs `operation` under one budget: a throwing task group with a timer child; when the timer
/// fires, the group is cancelled and the outcome is `deadlineExceeded` — unless `operation` still
/// returns, in which case success wins and its value is returned. `.max` or a non-positive budget
/// runs `operation` directly.
///
/// Used for establishing a lazy read (§5.1.3): `operation` is the whole `withRetry` loop, so node
/// selection, every attempt and the wait for the server's first response share one budget. The
/// expiry reaches `operation` as cancellation, which `withRetry` never retries and never answers
/// with `invalidate()`. A value `operation` returns after the expiry is returned, never dropped: a
/// dropped call would keep its lease, its stream slot and its shutdown handler.
///
/// An `operation` that fails after the expiry ends with `deadlineExceeded`, unless `connections` was
/// shut down by then: a shutdown, also one that lands while the expired `operation` unwinds, ends it
/// with `connectionClosed` (S14), the outcome a shutdown has everywhere else.
///
/// The caller's own cancellation is not the budget's: it reaches `operation` the same way and
/// whatever `operation` then throws is rethrown unchanged.
package func withEstablishmentBudget<T: Sendable>(
    milliseconds: Int,
    connections: ConnectionProvider,
    operation: @escaping @Sendable () async throws(KurrentError) -> T
) async throws(KurrentError) -> T {
    guard milliseconds != .max, milliseconds > 0 else {
        return try await operation()
    }

    do {
        return try await withThrowingTaskGroup(of: EstablishmentOutcome<T>.self, returning: T.self) { group in
            group.addTask { try await .opened(operation()) }
            group.addTask {
                do {
                    try await Task.sleep(for: .milliseconds(milliseconds))
                    return .expired
                } catch {
                    return .timerCancelled
                }
            }

            var expired = false
            while true {
                let next: EstablishmentOutcome<T>?
                do {
                    next = try await group.next()
                } catch {
                    // The operation failed; after the expiry, because the expiry cancelled it, or
                    // because the provider shut down, which wins: the caller sees connectionClosed.
                    if expired {
                        throw connections.isShutdown ? KurrentError.connectionClosed : KurrentError.deadlineExceeded
                    }
                    throw error
                }
                switch next {
                case let .opened(value)?:
                    group.cancelAll()
                    return value
                case .expired?:
                    expired = true
                    group.cancelAll()
                case .timerCancelled?:
                    continue
                case nil:
                    // Unreachable: the operation child either returns a value or throws.
                    throw KurrentError.deadlineExceeded
                }
            }
        }
    } catch let error as KurrentError {
        throw error
    } catch {
        throw .internalClientError(reason: "withEstablishmentBudget: operation failed – \(error)")
    }
}
