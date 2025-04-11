//
//  CurrentRevisionOption.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/4/11.
//

extension KurrentError {
    public enum CurrentRevisionOption: Sendable {
        case noStream
        case revision(UInt64)
    }
    
    public enum ExpectedRevisionOption: Sendable {
        case any
        case streamExists
        case noStream
        case revision(UInt64)
    }

}
