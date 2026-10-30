import KurrentDB
import Synchronization

/// A client lent by the pool for one independent KurrentDB instance; `withBorrowedClient(_:)`
/// passes it to its closure and gives it back when the closure returns or throws.
///
/// Giving it back closes the client's connections before the instance returns to the pool: every
/// later call on ``client``, on a facade made from it or on a `ReadCall` or `Subscription` kept past
/// the closure ends with `KurrentError.connectionClosed`, so nothing kept after give-back ever runs
/// against an instance the next borrower holds. Iterate inside the closure and return values, not
/// calls, facades or clients.
///
/// Give-back happens once: `withBorrowedClient(_:)` calls it, and `deinit` does it if nobody did.
/// It closes the connections with the provider's shutdown, not `KurrentDBClient.shutdown()`, because
/// it must wait until that shutdown has ended every call, which `KurrentDBClient.shutdown()` only
/// initiates. If the client's own `shutdown()` races give-back, give-back still waits until
/// that shutdown has ended every call before releasing the instance: the provider's shutdown
/// handlers (lazy reads) and its dedicated connections' close hooks (subscriptions) included.
public final class BorrowedClient: Sendable {
    public let client: KurrentDBClient
    private let lease: KurrentDBPool.Lease
    private struct State {
        /// Set by the first give-back, `giveBack()` or `deinit`; a later one does nothing.
        var started = false
        /// Set once that give-back has finished.
        var finished = false
    }

    private let state = Mutex(State())

    /// `true` once give-back has finished: the client's connections are closed, every call they
    /// carried has ended and the instance is back in the pool. `false` while `giveBack()` is still
    /// waiting for that, so a `true` never precedes the closed connections it promises.
    public var isGivenBack: Bool { state.withLock { $0.finished } }

    package init(client: KurrentDBClient, lease: KurrentDBPool.Lease) {
        self.client = client
        self.lease = lease
    }

    /// Closes the client's connections, waits until every call they carried has ended (reads through
    /// the shutdown handlers, subscriptions through the dedicated connections' close hooks), then
    /// returns the instance to the pool that lent it; ``isGivenBack`` becomes `true` after that. A
    /// second call does nothing (it does not wait for the first).
    package func giveBack() async {
        let shouldRelease = state.withLock { state in
            defer { state.started = true }
            return !state.started
        }
        guard shouldRelease else { return }
        await client.selector.connections.shutdownAwaitingHandlers()
        await lease.giveBack()
        state.withLock { $0.finished = true }
    }

    deinit {
        guard state.withLock({ !$0.started }) else { return }
        let connections = client.selector.connections
        connections.shutdown()
        let lease = lease
        Task {
            // A shutdown racing this one may still be running its handlers.
            await connections.shutdownAwaitingHandlers()
            await lease.giveBack()
        }
    }
}
