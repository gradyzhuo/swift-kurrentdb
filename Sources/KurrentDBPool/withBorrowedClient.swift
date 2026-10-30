import KurrentDB

/// Lends a client for one independent KurrentDB instance from the pool, runs `action` with it and
/// gives it back before returning, whether `action` returns or throws. Giving it back is awaited,
/// not deferred to a `Task`, so the instance is back in the pool when this function returns.
///
/// Giving it back first closes the borrowed client's connections: every call still running on
/// them ends with `KurrentError.connectionClosed`, and so does every later call on the client, on a
/// facade made from it, or on a `ReadCall` or `Subscription` kept past the closure. Only then does
/// the instance return to the pool, so nothing kept from this borrow ever runs against an instance
/// the next borrower holds. Iterate inside `action` and return values, not calls, facades or
/// clients.
///
/// Returns `nil` without calling `action` when no instance can be lent: the pool is empty, the
/// calling task is cancelled before one is lent, `maxAttempts` is not positive, or none of up to
/// `maxAttempts` candidates answered node selection (a later attempt does not wait: when no other
/// instance is idle, it gives up). When every instance is busy, the first attempt waits until one
/// is given back.
///
/// This is the only public entry point of `KurrentDBPool`. `BorrowedClient` is public because
/// `action` receives it, but giving it back is not public: this function always does it.
public func withBorrowedClient<T: Sendable>(
    numberOfThreads: Int = 1,
    maxAttempts: Int = 3,
    _ action: (BorrowedClient) async throws -> T
) async rethrows -> T? {
    guard let borrowed = await KurrentDBPool.borrow(numberOfThreads: numberOfThreads, maxAttempts: maxAttempts) else {
        return nil
    }
    do {
        let result = try await action(borrowed)
        await borrowed.giveBack()
        return result
    } catch {
        await borrowed.giveBack()
        throw error
    }
}
