//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/11/27.
//

import Foundation
import GRPCSupport

@available(macOS 13.0, *)
extension Projections {
    
    public struct Disable: UnaryUnary {
        public typealias Request = GenericGRPCRequest<EventStore_Client_Projections_DisableReq>
        public typealias Response = DiscardedResponse<EventStore_Client_Projections_DisableResp>
        
        public let name: String
        public let options: Options
        
        init(name: String, options: Options) {
            self.name = name
            self.options = options
        }
        
        public func build() throws -> Request.UnderlyingMessage {
            return .with{
                $0.options = options.build()
                $0.options.name = name
            }
        }
        
    }
    
}

@available(macOS 13.0, *)
extension Projections.Disable{
    public final class Options: EventStoreOptions {
        
        public typealias UnderlyingMessage = EventStore_Client_Projections_DisableReq.Options
        
        var options: UnderlyingMessage
        
        public init() {
            self.options = .with{
                $0.writeCheckpoint = false
            }
        }
        
        
        public func build() -> UnderlyingMessage {
            return options
        }
        
        @discardableResult
        public func writeCheckpoint(enabled: Bool) -> Self {
            self.options.writeCheckpoint = enabled
            return self
        }
        
    }
}
