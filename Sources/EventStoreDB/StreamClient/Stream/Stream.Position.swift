//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2024/5/21.
//

import Foundation

extension Stream {
    
    public struct Position: Sendable {
        public let commit: UInt64
        public let prepare: UInt64
        
        public init(commit: UInt64, prepare: UInt64? = nil) {
            self.commit = commit
            self.prepare = prepare ?? commit
        }
    }
    
}

extension Stream.Position {
    public enum Option {
        case noPosition
        case position(Stream.Position)
    }
}
