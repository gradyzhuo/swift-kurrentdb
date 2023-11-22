//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/10/31.
//

import Foundation
import SwiftProtobuf

protocol EventStoreOptions {
    associatedtype UnderlyingMessage: Message
    
    var options: UnderlyingMessage { get }
    
}