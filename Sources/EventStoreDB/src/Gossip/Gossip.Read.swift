//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/12/19.
//

import Foundation
import GRPCSupport

@available(macOS 13.0, *)
extension GossipClient {
    
    public struct Read: UnaryUnary {
        public typealias Request = GenericGRPCRequest<EventStore_Client_Empty>
        
    }

}


@available(macOS 13.0, *)
extension GossipClient.Read {
    
    public struct Response: GRPCResponse {
        public typealias UnderlyingMessage = EventStore_Client_Gossip_ClusterInfo
        
        let members: [MemberInfo]
        
        public init(from message: UnderlyingMessage) throws {
            self.members = try message.members.map{
                try .init(from: $0)
            }
        }
        
    }
    
    
}

@available(macOS 13.0, *)
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
            self.instanceId = uuid
            self.timeStamp = TimeInterval(message.timeStamp)
            self.state = message.state
            self.isAlive = message.isAlive
            self.httpEndPoint = .init(host: message.httpEndPoint.address, port: message.httpEndPoint.port)
            
        }
    }
    
    
    
}

