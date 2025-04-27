//
//  NodeConnnection.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/4/20.
//

import Foundation

public actor NodeSelector: Sendable {
    
    let id: UUID?
    let settings: ClientSettings
    var previousCandidates: [Gossip.MemberInfo]
    var selectedNode: Node?
    var discover: NodeDiscover
    
    internal init(settings: ClientSettings) {
        self.id = nil
        self.settings = settings
        self.previousCandidates = []
        self.discover = .init(settings: settings, previousCandidates: [])
    }
    
    package func select() async throws(KurrentError) -> Node {
        guard let selectedNode else {
            guard let memberInfo = try await self.discover.next() else {
                throw .notLeaderException
            }
            let node = try Node(endpoint: memberInfo.httpEndPoint, settings: settings)
            self.selectedNode = node
            return node
        }
        return selectedNode
    }
    
    package func select<T: Sendable>(perform: @Sendable (_ node: Node) async throws -> T) async throws(KurrentError) -> T {
        let node = try await self.select()
        return try await withRethrowingError(usage: #function){
            try await perform(node)
        }
    }
}

public actor NodeDiscover: AsyncIteratorProtocol, Sendable{
    public typealias Element = Gossip.MemberInfo
    
    let settings: ClientSettings
    private let previousCandidates: [Gossip.MemberInfo]
    
    init(settings: ClientSettings, previousCandidates: [Gossip.MemberInfo]) {
        self.settings = settings
        self.previousCandidates = []
    }
    
    public func next() async throws(KurrentError) -> Gossip.MemberInfo? {
        switch settings.clusterMode {
        case let .standalone(endpoint):
            return try await discover(seed: endpoint, nodePreference: .leader)
        case let .gossipCluster(seeds, nodePreference, timeout):
            for seed in seeds {
                return try await discover(seed: seed, nodePreference: nodePreference)
            }
            return nil
        }
    }
    
    func discover(seed: Endpoint, nodePreference: TopologyClusterMode.NodePreference) async throws(KurrentError) ->Gossip.MemberInfo?{
        let readGossip = Gossip.Read()
        let memberInfos = try await readGossip.perform(endpoint: seed, settings: settings, callOptions: .defaults)
        
        let sortedMembers = memberInfos.sorted { lhs, rhs in
            nodePreference.priority(state: lhs.state) < nodePreference.priority(state: rhs.state)
        }
        //還要檢查不在previousCandidates裡
        if let memberInfo = sortedMembers.first(where: { $0.isAlive }) {
            return memberInfo
        }
        return nil
    }
}



