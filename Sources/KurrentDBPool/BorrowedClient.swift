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
/// It closes the connections with the provider's shutdown, not `KurrentDBClient.shutdown()`, whose
/// synchronous event-loop-group shutdown must not run on an event-loop thread (and `deinit` can run
/// on any thread). If the client's own `shutdown()` races give-back, give-back still waits until
/// that shutdown has ended every call before releasing the instance: the provider's shutdown
/// handlers (lazy reads) and its dedicated connections' close hooks (subscriptions) included.
public final class BorrowedClient: Sendable {
    public let client: KurrentDBClient
    private let lease: KurrentDBPool.Lease
    private let state = Mutex(false)

    /// `true` once the client has been given back; its connections are closed by then.
    public var isGivenBack: Bool { state.withLock { $0 } }

    package init(client: KurrentDBClient, lease: KurrentDBPool.Lease) {
        self.client = client
        self.lease = lease
    }

    /// Closes the client's connections, waits until every call they carried has ended (reads through
    /// the shutdown handlers, subscriptions through the dedicated connections' close hooks), then
    /// returns the instance to the pool that lent it. A second call does nothing.
    package func giveBack() async {
        let shouldRelease = state.withLock { given in
            defer { given = true }
            return !given
        }
        guard shouldRelease else { return }
        await client.selector.connections.shutdownAwaitingHandlers()
        await lease.giveBack()
    }

    deinit {
        guard state.withLock({ !$0 }) else { return }
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
