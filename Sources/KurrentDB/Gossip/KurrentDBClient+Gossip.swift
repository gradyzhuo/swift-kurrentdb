//
//  KurrentDBClient+Gossip.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/2/16.
//

// MARK: - Gossip Operations

extension KurrentDBClient {
    /// Reads the current cluster topology via the gossip protocol.
    ///
    /// Tries each configured endpoint in turn and returns the first successful member list.
    /// Falls back to a direct call on the first candidate and rethrows any error if that also fails.
    ///
    /// ```swift
    /// let members = try await client.readCluster()
    /// if let leader = members.first(where: { $0.state == .leader && $0.isAlive }) {
    ///     print("Leader endpoint: \(leader.httpEndPoint)")
    /// }
    /// ```
    ///
    /// - Parameter timeout: Maximum wait per gossip request. Defaults to the client's configured gossip timeout.
    /// - Returns: An array of ``Gossip/MemberInfo`` representing all known cluster members.
    /// - Throws: `KurrentError` if the gossip request fails or all endpoints are unreachable.
    public func readCluster(timeout: Duration? = nil) async throws(KurrentError) -> [Gossip.MemberInfo] {
        let candidates = switch settings.clusterMode {
        case let .standalone(endpoint):
            [endpoint]
        case let .dns(endpoint):
            [endpoint]
        case let .seeds(candidates):
            candidates
        }

        let gossipTimeout = timeout ?? settings.gossipTimeout
        for candidate in candidates {
            let gossip = Gossip(
                endpoint: candidate,
                settings: settings,
                callOptions: defaultCallOptions,
                eventLoopGroup: eventLoopGroup
            )
            if let members = try? await gossip.read(timeout: gossipTimeout), !members.isEmpty {
                return members
            }
        }

        return try await Gossip(
            endpoint: candidates[0],
            settings: settings,
            callOptions: defaultCallOptions,
            eventLoopGroup: eventLoopGroup
        ).read(timeout: gossipTimeout)
    }
}
