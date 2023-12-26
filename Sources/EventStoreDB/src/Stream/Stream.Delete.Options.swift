//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/10/31.
//

import Foundation
import GRPCSupport

@available(macOS 13.0, *)
extension StreamClient.Delete {
    public final class Options: EventStoreOptions {
        public typealias UnderlyingMessage = EventStore_Client_Streams_DeleteReq.Options
        
        var options: UnderlyingMessage
        
        public init() {
            self.options = .with{
                $0.noStream = .init()
            }
        }
        
        public func build() -> UnderlyingMessage {
            return options
        }
        
        @discardableResult
        public func expected(revision: StreamClient.Revision)->Self{
            switch revision {
            case .any:
                options.any = .init()
            case .noStream:
                options.noStream = .init()
            case .streamExists:
                options.streamExists = .init()
            case .revision(let rev):
                options.revision = rev
            }
            return self
        }
        
        
        
    }
}

