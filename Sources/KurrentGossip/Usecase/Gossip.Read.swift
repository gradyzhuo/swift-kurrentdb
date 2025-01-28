//
//  Gossip.Read.swift
//  KurrentGossip
//
//  Created by Grady Zhuo on 2023/12/19.
//

import Foundation
import GRPCCore
import GRPCEncapsulates
import KurrentCore

extension Gossip {
    public struct Read: UnaryUnary {
        package typealias ServiceClient = Client
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.Read.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.Read.Output
        public typealias Response = [Read.MemberInfo]

        package func send(client: ServiceClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            try await client.read(request: request, options: callOptions) {
                try $0.message.members.map {
                    try .init(from: $0)
                }
            }
        }
    }
}

extension Gossip.Read {
    public enum NodeState: Sendable {
        package typealias UnderlyingMessage = EventStore_Client_Gossip_MemberInfo.VNodeState

        case initializing
        case discoverLeader
        case unknown
        case preReplica
        case catchingUp
        case clone
        case follower
        case preLeader
        case leader
        case manager
        case shuttingDown
        case shutdown
        case readOnlyLeaderless
        case preReadOnlyReplica
        case readOnlyReplica
        case resigningLeader
        case UNRECOGNIZED(Int)

        package init(from message: UnderlyingMessage) {
            switch message {
            case .initializing:
                self = .initializing
            case .discoverLeader:
                self = .discoverLeader
            case .unknown:
                self = .unknown
            case .preReplica:
                self = .preReplica
            case .catchingUp:
                self = .catchingUp
            case .clone:
                self = .clone
            case .follower:
                self = .follower
            case .preLeader:
                self = .preLeader
            case .leader:
                self = .leader
            case .manager:
                self = .manager
            case .shuttingDown:
                self = .shuttingDown
            case .shutdown:
                self = .shutdown
            case .readOnlyLeaderless:
                self = .readOnlyLeaderless
            case .preReadOnlyReplica:
                self = .preReadOnlyReplica
            case .readOnlyReplica:
                self = .readOnlyReplica
            case .resigningLeader:
                self = .resigningLeader
            case let .UNRECOGNIZED(enumValue):
                self = .UNRECOGNIZED(enumValue)
            }
        }
    }

    public struct MemberInfo: GRPCResponse {
        package typealias UnderlyingMessage = EventStore_Client_Gossip_MemberInfo

        public let instanceId: UUID
        public let timeStamp: TimeInterval
        public let state: NodeState
        public let isAlive: Bool
        public let httpEndPoint: ClientSettings.Endpoint

        package init(from message: UnderlyingMessage) throws {
            guard let uuid = message.instanceID.toUUID() else {
                throw ClientError.readResponseError(message: "The instance id not found.")
            }
            instanceId = uuid
            timeStamp = TimeInterval(message.timeStamp)
            state = .init(from: message.state)
            isAlive = message.isAlive
            httpEndPoint = .init(host: message.httpEndPoint.address, port: message.httpEndPoint.port)
        }
    }
}
