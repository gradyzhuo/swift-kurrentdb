//
//  NodeSelector.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2025/4/20.
//

import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2

/// Selects and caches the best available cluster node for client connections.
///
/// Wraps ``NodeDiscover`` to run gossip-based node discovery and caches the chosen
/// ``Node`` for the duration specified by `ClientSettings.nodeCacheTTL`. Call ``select()``
/// before every RPC; the cached node is returned until it expires or is invalidated.
public actor NodeSelector: Sendable {
    let id: UUID?
    let settings: ClientSettings
    var selectedNode: Node?
    var selectedNodeExpiry: Date?
    var discover: NodeDiscover

    init(settings: ClientSettings) {
        id = nil
        self.settings = settings
        discover = .init(settings: settings, previousCandidates: [])
    }

    /// Operation retry policy sourced from the client settings.
    nonisolated var retryPolicy: OperationRetryPolicy {
        settings.operationRetryPolicy
    }

    /// Returns the best available cluster node, using a cached result when still valid.
    ///
    /// Runs gossip-based discovery when the cache is empty or expired. Retries up to
    /// `ClientSettings.maxDiscoveryAttempts` times with `discoveryInterval` between attempts.
    ///
    /// - Returns: A ``Node`` ready to accept gRPC connections.
    /// - Throws: `KurrentError.serverError` if no reachable node is found within the attempt limit.
    public func select() async throws(KurrentError) -> Node {
        if let node = selectedNode, let expiry = selectedNodeExpiry, Date.now < expiry {
            return node
        }
        let node = try await withRethrowingError(usage: "") {
            guard let node = try await selectNode() else {
                throw KurrentError.serverError("Connection node not found.")
            }
            return node
        }
        self.selectedNode = node
        self.selectedNodeExpiry = Date.now.addingTimeInterval(settings.nodeCacheTTL.timeInterval)
        return node
    }

    /// Clears the cached node so the next ``select()`` call triggers fresh discovery.
    func invalidate() {
        logger.debug("[NodeSelector] Invalidating cached node, will re-discover on next select.")
        selectedNode = nil
        discover = .init(settings: settings, previousCandidates: [])
    }

    private func selectNode() async throws -> Node? {
        var attempts = 0

        while true {
            do {
                guard let endpoint = try await discover.next() else {
                    throw KurrentError.notLeaderException
                }

                var callOptions = CallOptions.defaults
                callOptions.timeout = settings.gossipTimeout

                let serviceFeaturesClient = ServerFeatures(endpoint: endpoint, settings: settings, callOptions: callOptions)
                let serverInfo = try await serviceFeaturesClient.getSupportedMethods()
                return Node(endpoint: endpoint, settings: settings, serverInfo: serverInfo)
            } catch {
                attempts += 1

                guard attempts < settings.maxDiscoveryAttempts else {
                    return nil
                }

                try await Task.sleep(for: settings.discoveryInterval)
                logger.debug("Starting new connection attempt")
                continue
            }
        }
    }
}

/// Iterates over cluster candidates via gossip to find the preferred reachable endpoint.
public actor NodeDiscover: AsyncIteratorProtocol, Sendable {
    public typealias Element = Endpoint

    let settings: ClientSettings
    var selectedEndpoint: Endpoint?
    private let previousCandidates: [Endpoint]

    init(settings: ClientSettings, previousCandidates _: [Gossip.MemberInfo]) {
        self.settings = settings
        previousCandidates = []
    }

    /// Returns the best endpoint discovered via gossip, or `nil` if no live member is found.
    ///
    /// Shuffles the candidate list, queries each candidate's gossip API, and returns the
    /// HTTP endpoint of the first alive member. Subsequent calls return the cached endpoint.
    ///
    /// - Returns: The preferred ``Endpoint`` for gRPC connections, or `nil` if discovery fails.
    /// - Throws: `KurrentError` if the gossip request to a candidate cannot be completed.
    public func next() async throws(KurrentError) -> Endpoint? {
        guard selectedEndpoint == nil else {
            return selectedEndpoint
        }

        let candidates = switch settings.clusterMode {
        case let .standalone(endpoint):
            [endpoint]
        case let .dns(endpoint):
            [endpoint]
        case let .seeds(candidates):
            candidates
        }

        for candidate in candidates.shuffled() {
            guard let memberInfo = try await discover(candidate: candidate) else {
                continue
            }

            let endpoint = memberInfo.httpEndPoint
            let leaderEndpoint = if !candidate.isLocalhost, endpoint.isLocalhost {
                candidate
            } else {
                endpoint
            }

            logger.info("Discovering: found best choice \(leaderEndpoint.host):\(leaderEndpoint.port) (\(memberInfo.state))")
            return leaderEndpoint
        }
        return nil
    }

    func discover(candidate: Endpoint) async throws(KurrentError) -> Gossip.MemberInfo? {
        logger.debug("Calling gossip endpoint on: \(candidate)")
        var callOptions = CallOptions.defaults
        callOptions.timeout = settings.gossipTimeout

        let gossipClient = Gossip(endpoint: candidate, settings: settings, callOptions: callOptions)
        let memberInfos = try await gossipClient.read(
                                                    timeout: settings.gossipTimeout,
                                                    notAllowedStates: [.manager, .shuttingDown, .shutdown])
        logger.debug("Candidate \(candidate) gossip info: \(memberInfos)")
        return memberInfos.first { $0.isAlive }
    }
}
