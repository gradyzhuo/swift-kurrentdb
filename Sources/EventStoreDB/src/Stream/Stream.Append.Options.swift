//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/10/29.
//

import Foundation
import GRPCSupport

@available(macOS 13.0, *)
extension StreamClient.Append {
    public final class Options: EventStoreOptions {
        public typealias UnderlyingMessage = Request.UnderlyingMessage.Options
        
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
        public func expected(revision: StreamClient.Revision<UnderlyingMessage.OneOf_ExpectedStreamRevision>)->Self{
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

