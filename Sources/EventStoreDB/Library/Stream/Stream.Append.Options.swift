//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/10/29.
//

import Foundation

@available(macOS 10.15, *)
extension Stream.Append {
    public class Options: EventStoreOptions {
        public typealias UnderlyingMessage = EventStore_Client_Streams_AppendReq.Options
        
        public var options: UnderlyingMessage
        
        public init() {
            self.options = .with{
                $0.any = .init()
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

