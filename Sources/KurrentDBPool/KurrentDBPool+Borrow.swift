import KurrentDB
import NIOCore
import NIOPosix

extension KurrentDBPool {
    /// package: outside callers cannot call this, only the public
    /// withBorrowedClient(_:). KurrentDBClient itself is not extended;
    /// KurrentDBPool does the lease, the construction and the wrapping here, in one go.
    ///
    /// acquire() only guarantees that nobody else holds this member in the ledger, not that it can
    /// be reached, so a short-lived ack client confirms it is alive once the lease is held. A
    /// candidate that fails is held back from the idle pool (so the same one is not drawn and tested
    /// again at once) and given back when this borrow() ends, to be probed again by the next call.
    ///
    /// The ack uses client.selector.select() (package-scoped, visible because KurrentDBPool is in
    /// the same package), not client.readCluster() as it once did.
    /// readCluster() only checks that the gossip seed can be reached, not that the address
    /// NodeSelector picks for the real RPCs can be reached too. Under Docker or NAT the two can
    /// differ: the seed is reachable while the address gossip reports is not (a container with
    /// no advertised address, for example, which is the problem met and fixed while this target
    /// was written). readCluster() would call it alive and hand the borrower a client whose first
    /// real RPC fails. selector.select() takes the same path perform() takes before every real
    /// RPC (the gossip probe, resolving the endpoint, the ServerFeatures check), and is the only
    /// probe that guarantees a real operation succeeds once the ack has.
    /// NodeDiscover.discover(candidate:) already filters out .manager, .shuttingDown and
    /// .shutdown through notAllowedStates, so that is not repeated here in a copy that could
    /// drift from NodeSelector's own logic.
    ///
    /// select() is bounded: NodeDiscover.discover(candidate:) and the ServerFeatures check each
    /// build their own CallOptions from settings.gossipTimeout (not from the defaultCallOptions
    /// given to KurrentDBClient), and selectNode() around them is capped at
    /// maxDiscoveryAttempts, so it cannot hang without end.
    ///
    /// Each round takes one candidate and tests it at once. The first round uses acquire(), which
    /// queues: waiting once is worth it when every member is busy. Later rounds change candidate
    /// with tryAcquire(), which does not queue, and stop at once when there is none left, instead of
    /// waiting for a release() only the candidates this call holds back could cause. No extra
    /// candidate is taken after the last round on purpose: it would be neither tested nor added to
    /// rejected, and would stay busy forever, a lease leak that does happen.
    ///
    /// Note: the short-lived ack client and the BorrowedClient handed to the caller are two
    /// separate instances. Once the ack passes, that client is dropped and a new one is built with
    /// the normal settings for the caller; the instance the ack probed with is not handed on.
    package static func borrow(eventLoopGroup: any EventLoopGroup = .singletonMultiThreadedEventLoopGroup, maxAttempts: Int = 3) async -> BorrowedClient? {
        guard maxAttempts > 0 else { return nil }
        var rejected: [Lease] = []

        for attempt in 0..<maxAttempts {
            let next: Lease?
            if attempt == 0 {
                next = await shared.acquire()
            } else {
                next = await shared.tryAcquire()
            }
            guard let candidate = next else { break }

            let ackClient = KurrentDBClient(settings: candidate.settings, eventLoopGroup: eventLoopGroup)
            let isReachable = (try? await ackClient.selector.select()) != nil
            ackClient.shutdown()

            guard isReachable else {
                rejected.append(candidate)
                continue
            }

            for lease in rejected { await lease.giveBack() }
            let client = KurrentDBClient(settings: candidate.settings, eventLoopGroup: eventLoopGroup)
            return BorrowedClient(client: client, lease: candidate)
        }

        for lease in rejected { await lease.giveBack() }
        return nil
    }
}
