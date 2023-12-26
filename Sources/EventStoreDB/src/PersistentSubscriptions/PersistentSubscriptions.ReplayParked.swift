//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/12/11.
//

import Foundation
import GRPCSupport

@available(macOS 13.0, *)
extension PersistentSubscriptionsClient {
    public struct ReplayParked: UnaryUnary {
        public typealias Request = GenericGRPCRequest<EventStore_Client_PersistentSubscriptions_ReplayParkedReq>
        public typealias Response = DiscardedResponse<EventStore_Client_PersistentSubscriptions_ReplayParkedResp>
        
        let streamSelection: StreamSelection
        let groupName: String
        let options: Options
        
        
        public func build() throws -> EventStore_Client_PersistentSubscriptions_ReplayParkedReq {
            
            return try .with{
                $0.options = options.build()
                $0.options.groupName = groupName
                
                switch streamSelection {
                case .all:
                    $0.options.all = .init()
                case .specified(let streamIdentifier):
                    $0.options.streamIdentifier = try streamIdentifier.build()
                }
            }
            
        }
    }
}

@available(macOS 13.0, *)
extension PersistentSubscriptionsClient.ReplayParked{
    public final class Options: EventStoreOptions {
        public enum StopAtOption {
            case position(position: Int64)
            case noLimit
        }
        
        public typealias UnderlyingMessage = Request.UnderlyingMessage.Options
        var message: UnderlyingMessage
        
        init(){
            self.message = .init()
            self.stop(at: .noLimit)
        }
        
        @discardableResult
        public func stop(at option: StopAtOption) -> Self{
            switch option {
            case .position(let position):
                self.message.stopAt = position
            case .noLimit:
                self.message.noLimit = .init()
            }
            return self
        }
        
        public func build() -> PersistentSubscriptionsClient.ReplayParked.Request.UnderlyingMessage.Options {
            return self.message
        }
    }
}
