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
            
            let serviceFeaturesClient = ServerFeatures(endpoint: memberInfo.httpEndPoint, settings: settings)
            let serverInfo = try await serviceFeaturesClient.getSupportedMethods()
            
            self.previousCandidates.append(memberInfo)
            let node = Node(endpoint: memberInfo.httpEndPoint, settings: settings, serverInfo: serverInfo)
            self.selectedNode = node
            return node
        }
        
        return selectedNode
    }
}

struct NodeInfo{
    var id: UUID
    var endpoint: Endpoint?
    var secure: Bool
    var connection: GRPCClient<HTTP2ClientTransport.Posix>
    var serverInfo: ServerFeatures.ServiceInfo
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
            switch settings.clusterMode {
            case let .standalone(endpoint):
                return try await discover(candidate: endpoint)
            case let .dns(endpoint):
                return try await discover(candidate: endpoint)
            case let .seeds(candidates):
                for candidate in candidates {
                    return try await discover(candidate: candidate)
                }
                return nil
            }
        }
        return selectedMember
    }
    
    func discover(candidate: Endpoint) async throws(KurrentError) ->Gossip.MemberInfo?{
    
        logger.debug("Calling gossip endpoint on: \(candidate)");
        var callOptions = CallOptions.defaults
        callOptions.timeout = settings.gossipTimeout
        
        let gossipClient = Gossip(endpoint: candidate, settings: settings, callOptions: callOptions)
        let memberInfos = try await gossipClient.read()
        
        logger.debug("Candidate \(candidate) gossip info: \(memberInfos)")
        
        let sortedMembers = memberInfos.sorted { lhs, rhs in
            settings.nodePreference.priority(state: lhs.state) < settings.nodePreference.priority(state: rhs.state)
        }
        
        let notAllowedState: [Gossip.VNodeState] = [.manager, .shuttingDown, .shutdown]
        let member = sortedMembers.first(where: { member in  member.isAlive && !notAllowedState.contains(member.state) })
        
        if let member = member{
            logger.info( "Discovering: found best choice \(member.httpEndPoint.host):\(member.httpEndPoint.port) (\(member.state)"
                    )
        }
        
        return member
    }
}



