//
//  Gossip.Read.swift
//
//
//  Created by Grady Zhuo on 2023/12/19.
//

import Foundation
import GRPCEncapsulates

extension GossipClient {
    public struct Read: UnaryUnary {
        public typealias Request = GenericGRPCRequest<EventStore_Client_Empty>
    }
}

extension GossipClient.Read {
    public struct Response: GRPCResponse {
        public typealias UnderlyingMessage = EventStore_Client_Gossip_ClusterInfo

        let members: [MemberInfo]

        public init(from message: UnderlyingMessage) throws {
            members = try message.members.map {
                try .init(from: $0)
            }
        }
    }
}

extension GossipClient.Read.Response {
    public struct MemberInfo: GRPCResponse {
        public typealias UnderlyingMessage = EventStore_Client_Gossip_MemberInfo

        public let instanceId: UUID
        public let timeStamp: TimeInterval
        public let state: UnderlyingMessage.VNodeState
        public let isAlive: Bool
        public let httpEndPoint: ClientSettings.Endpoint

        public init(from message: UnderlyingMessage) throws {
            guard let uuid = message.instanceID.toUUID() else {
                throw ClientError.readResponseError(message: "The instance id not found.")
            }
            instanceId = uuid
            timeStamp = TimeInterval(message.timeStamp)
            state = message.state
            isAlive = message.isAlive
            httpEndPoint = .init(host: message.httpEndPoint.address, port: message.httpEndPoint.port)
        }
    }
}
