//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/12/5.
//

import Foundation
import GRPCSupport

@available(macOS 13.0, *)
extension ProjectionsClient {
    public struct Reset: UnaryUnary {
        public typealias Request = GenericGRPCRequest<EventStore_Client_Projections_ResetReq>
        public typealias Response = DiscardedResponse<EventStore_Client_Projections_ResetResp>
        
        let name: String
        let options: Options
        
        init(name: String, options: Options) {
            self.name = name
            self.options = options
        }
        
        public func build() throws -> Request.UnderlyingMessage {
            return .with{
                $0.options = self.options.build()
                $0.options.name = name
            }
        }
        
        
    }
    
    
}

@available(macOS 13.0, *)
extension ProjectionsClient.Reset {
    public final class Options:  EventStoreOptions{
        
        public typealias UnderlyingMessage = Request.UnderlyingMessage.Options
        
        var options: UnderlyingMessage
        
        public init() {
            self.options = .with{
                $0.writeCheckpoint = false
            }
        }
        
        public func writeCheckpoint(enable: Bool)->Self{
            self.options.writeCheckpoint = enable
            return self
        }
        
        public func build() -> ProjectionsClient.Reset.Request.UnderlyingMessage.Options {
            return options
        }
        
        
        
        
    }
}
