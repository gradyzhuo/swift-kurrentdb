//
//  Gossip.swift
//  KurrentGossip
//
//  Created by Grady Zhuo on 2023/10/17.
//
import Foundation
import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix
import Logging
import NIO

public struct Gossip {
    package typealias UnderlyingClient = EventStore_Client_Gossip_Gossip.Client<HTTP2ClientTransport.Posix>

    internal let node: Node
    public let callOptions: CallOptions
    public let eventLoopGroup: EventLoopGroup

    internal init(node: Node, callOptions: CallOptions = .defaults, eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup) {
        self.node = node
        self.callOptions = callOptions
        self.eventLoopGroup = eventLoopGroup
    }
}

extension Gossip {
    public func read() async throws(KurrentError) -> [MemberInfo] {
        let usecase = Read()
        return try await usecase.perform(node: node, callOptions: callOptions).reduce(into: .init()) { partialResult, memberInfo in
            partialResult.append(memberInfo)
        }
    }
    
//    public func findAll()async throws(KurrentError) -> [MemberInfo]{
//        if case let .gossipCluster(seeds, nodePreference, timeout, discoveryInterval, maxDiscoveryAttempts) = settings.clusterMode{
//            
//        }
//        try await withThrowingTaskGroup { group in
//            group.addTask {
//                return ""
//            }
//            
//            try await group.waitForAll()
//        }
//    }
}
