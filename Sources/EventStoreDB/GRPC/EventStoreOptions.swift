//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/10/31.
//

import Foundation
import SwiftProtobuf

public protocol EventStoreOptions {
    associatedtype UnderlyingMessage: Message
    
    func build() -> UnderlyingMessage
    
}

