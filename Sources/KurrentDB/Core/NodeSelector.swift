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

    /// 這個 client 所有 gRPC 連線的來源。`nonisolated let`:同步的
    /// `KurrentDBClient.shutdown()` 需要在不進入 actor 的情況下關閉它。
    nonisolated let connections: ConnectionProvider

    init(settings: ClientSettings) {
        id = nil
        self.settings = settings
        connections = ConnectionProvider(settings: settings)
        discover = .init(settings: settings, connections: connections, previousCandidates: [])
    }

    /// Operation retry policy sourced from the client settings.
    nonisolated var retryPolicy: OperationRetryPolicy {
        settings.operationRetryPolicy
    }

    /// 測試用:直接放入快取,略過 discovery,讓 `perform(selector:)` 能離線走到 `perform(node:)`。
    package func cacheNodeForTesting(_ node: Node) {
        selectedNode = node
        selectedNodeExpiry = Date.now.addingTimeInterval(settings.nodeCacheTTL.timeInterval)
    }

    /// Returns the best available cluster node, using a cached result when still valid.
    ///
    /// Runs gossip-based discovery when the cache is empty or expired. Retries up to
    /// `ClientSettings.maxDiscoveryAttempts` times with `discoveryInterval` between attempts.
    ///
    /// - Returns: A ``Node`` ready to accept gRPC connections.
    /// - Throws: `KurrentError.serverError` if no reachable node is found within the attempt limit.
    public func select() async throws(KurrentError) -> Node {
        // 不論 node 快取是否過期,shutdown 之後一律是 connectionClosed。否則快取過期時
        // 會進入 discovery,把探測的 connectionClosed 當成一般失敗重試,最後回報成
        // 「找不到 node」。
        guard !connections.isShutdown else {
            throw .connectionClosed
        }
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
        discover = .init(settings: settings, connections: connections, previousCandidates: [])
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

                let serviceFeaturesClient = ServerFeatures(endpoint: endpoint, settings: settings, connections: connections, callOptions: callOptions)
                let serverInfo = try await serviceFeaturesClient.getSupportedMethods()
                return Node(endpoint: endpoint, settings: settings, serverInfo: serverInfo, connections: connections)
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
    /// 與 NodeSelector 同一個 provider:探測走的是同一份共用連線快取,
    /// 在這裡另建 provider 會讓復用失效。
    private let connections: ConnectionProvider

    init(settings: ClientSettings, connections: ConnectionProvider, previousCandidates _: [Gossip.MemberInfo]) {
        self.settings = settings
        self.connections = connections
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
            let leaderEndpoint = switch settings.endpointResolutionPreference {
            case .userConfigured:
                candidate
            case .gossipReported:
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

        let gossipClient = Gossip(endpoint: candidate, settings: settings, connections: connections, callOptions: callOptions)
        let memberInfos = try await gossipClient.read(
                                                    timeout: settings.gossipTimeout,
                                                    notAllowedStates: [.manager, .shuttingDown, .shutdown])
        logger.debug("Candidate \(candidate) gossip info: \(memberInfos)")
        return memberInfos.first { $0.isAlive }
    }
}
