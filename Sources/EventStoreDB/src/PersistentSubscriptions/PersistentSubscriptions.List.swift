//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/12/11.
//

import Foundation
import GRPCSupport


extension PersistentSubscriptionsClient {
    public struct List: UnaryUnary {
        public typealias Request = GenericGRPCRequest<EventStore_Client_PersistentSubscriptions_ListReq>
        
        let options: Options
        
        init(options: Options){
            self.options = options
        }
        
        public func build() throws -> Request.UnderlyingMessage {
            return .with{
                $0.options = self.options.build()
            }
        }
    }
    
}


extension PersistentSubscriptionsClient.List{
    
    public struct Response: GRPCResponse {
        public typealias UnderlyingMessage = EventStore_Client_PersistentSubscriptions_ListResp
        
        var subscriptions: [PersistentSubscriptionsClient.SubscriptionInfo]
        
        public init(from message: UnderlyingMessage) throws {
            self.subscriptions = message.subscriptions.map{ .init(from: $0)  }
        }
        
    }
    
}


extension PersistentSubscriptionsClient.List {
    public final class Options: EventStoreOptions {
        public typealias UnderlyingMessage = Request.UnderlyingMessage.Options
        
        var message: UnderlyingMessage
        
        init() {
            self.message = .init()
            self.listAllScriptions()
        }
        
        @discardableResult
        public func listAllScriptions() ->Self{
            self.message.listAllSubscriptions = .init()
            return self
        }
        
        @discardableResult
        public func listForStream(_ selection: PersistentSubscriptionsClient.StreamSelection) throws ->Self{
            switch selection {
            case .all:
                self.message.listForStream.all = .init()
            case .specified(streamIdentifier: let streamIdentifier):
                self.message.listForStream.stream = try streamIdentifier.build()
            }
            return self
        }
        
        public func build() -> UnderlyingMessage {
            return self.message
        }
    }
}
