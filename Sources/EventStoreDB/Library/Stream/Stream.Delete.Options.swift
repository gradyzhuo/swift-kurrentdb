//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/10/31.
//

import Foundation

@available(macOS 10.15, *)
extension Stream.Delete {
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
        public func expected(revision: Stream.Revision<UnderlyingMessage.OneOf_ExpectedStreamRevision>)->Self{
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

