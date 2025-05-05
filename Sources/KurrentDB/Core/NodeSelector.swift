//
//  NodeConnnection.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/4/20.
//

import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2

public actor NodeSelector: Sendable {    
    let id: UUID?
    let settings: ClientSettings
    var selectedNode: Node?
    var discover: NodeDiscover
    
    internal init(settings: ClientSettings) {
        self.id = nil
        self.settings = settings
        self.discover = .init(settings: settings, previousCandidates: [])
    }
    
    public func select() async throws(KurrentError) -> Node {
        guard let selectedNode else {
            let node = try await withRethrowingError(usage: "") {
                guard let node = try await selectNode() else {
                    throw KurrentError.serverError("Connection node not found.")
                }
                return node
            }
            self.selectedNode = node
            return node
        }
        
        return selectedNode
    }
    
    private func selectNode() async throws -> Node? {
        var attempts = 0
        
        while true {
            do{
                guard let memberInfo = try await self.discover.next() else {
                    throw KurrentError.notLeaderException
                }
                
                var callOptions = CallOptions.defaults
                callOptions.timeout = settings.gossipTimeout
                
                let serviceFeaturesClient = ServerFeatures(endpoint: memberInfo.httpEndPoint, settings: settings, callOptions: callOptions)
                let serverInfo = try await serviceFeaturesClient.getSupportedMethods()
                return Node(endpoint: memberInfo.httpEndPoint, settings: settings, serverInfo: serverInfo)
            }catch{
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

public actor NodeDiscover: AsyncIteratorProtocol, Sendable{
    public typealias Element = Gossip.MemberInfo
    
    let settings: ClientSettings
    var selectedMember: Gossip.MemberInfo?
    private let previousCandidates: [Gossip.MemberInfo]
    
    init(settings: ClientSettings, previousCandidates: [Gossip.MemberInfo]) {
        self.settings = settings
        self.previousCandidates = []
    }
    
    public func next() async throws(KurrentError) -> Gossip.MemberInfo? {
        guard let selectedMember else {
            let candidates = switch settings.clusterMode {
            case let .standalone(endpoint):
                [endpoint]
            case let .dns(endpoint):
                [endpoint]
            case let .seeds(candidates):
                candidates
            }
            
            for candidate in candidates.shuffled() {
                return try await discover(candidate: candidate)
            }
            return nil
        }
        return selectedMember
    }
    
    func discover(candidate: Endpoint) async throws(KurrentError) ->Gossip.MemberInfo?{
    
        logger.debug("Calling gossip endpoint on: \(candidate)");
        var callOptions = CallOptions.defaults
        callOptions.timeout = settings.gossipTimeout
        
        let gossipClient = Gossip(endpoint: candidate, settings: settings, callOptions: callOptions)
        let memberInfos = try await gossipClient.read(timeout: settings.gossipTimeout)
        
        logger.debug("Candidate \(candidate) gossip info: \(memberInfos)")
        
        let sortedMembers = memberInfos.sorted { lhs, rhs in
            settings.nodePreference.priority(state: lhs.state) < settings.nodePreference.priority(state: rhs.state)
        }
        
        let notAllowedState: [Gossip.VNodeState] = [.manager, .shuttingDown, .shutdown]
        let member = sortedMembers.first(where: { member in  member.isAlive && !notAllowedState.contains(member.state) })
        
        if let member = member{
            logger.info( "Discovering: found best choice \(member.httpEndPoint.host):\(member.httpEndPoint.port) (\(member.state))"
                    )
        }
        
        return member
    }
}



