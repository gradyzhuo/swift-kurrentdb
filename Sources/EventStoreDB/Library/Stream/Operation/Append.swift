//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/10/22.
//

import Foundation

@available(macOS 10.15, *)
extension Stream {
    public struct Append {
        
        public enum CurrentRevisionOption {
            case noStream
            case revision(UInt64)
        }
        
    }
}


@available(macOS 10.15, *)
extension Stream.Identifier {
    
    internal func build(options: inout Stream.Append.Client.UnderlyingRequest.Options) throws{
        options.streamIdentifier = try self.build()
    }
}
