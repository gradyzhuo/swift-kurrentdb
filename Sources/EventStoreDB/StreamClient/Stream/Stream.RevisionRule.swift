//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2024/5/21.
//

import Foundation

extension Stream {
    
    public enum RevisionRule {
        case any
        case noStream
        case streamExists
        case revision(UInt64)
    }
    
}
