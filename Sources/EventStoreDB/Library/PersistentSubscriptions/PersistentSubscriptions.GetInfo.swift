//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/12/10.
//

import Foundation
import GRPCSupport

@available(macOS 10.15, *)
extension PersistentSubscriptions {
    public struct GetInfo: UnaryUnary {
        public typealias Request = GenericGRPCRequest<EventStore_Client_PersistentSubscriptions_GetInfoReq>
        
        
        let streamSelection: StreamSelection
        let groupName: String
        
        public func build() throws -> Request.UnderlyingMessage {
            return try .with{
                switch self.streamSelection {
                case .specified(let streamIdentifier):
                    $0.options.streamIdentifier = try streamIdentifier.build()
                case .all:
                    $0.options.all = .init()
                }
                $0.options.groupName = groupName
            }
        }
    }

}

@available(macOS 10.15, *)
extension PersistentSubscriptions.GetInfo{
    public struct Response: GRPCResponse{
        public typealias UnderlyingMessage = EventStore_Client_PersistentSubscriptions_GetInfoResp
        
        public let subscriptionInfo: PersistentSubscriptions.SubscriptionInfo
        
        public init(from message: UnderlyingMessage) throws {
            self.subscriptionInfo = .init(from: message.subscriptionInfo)
        }
    }
}
