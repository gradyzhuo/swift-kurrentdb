//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2024/5/25.
//

import Foundation
import XCTest
import Testing
@testable import EventStoreDB

final class ConnectionStringParserTests:XCTestCase {
    
    func testESDBSchemeParsedShouldSuccess() throws {
        "esdb://localhost:2113?tls=false"
    }
    
    func testESDBSchemeParsedShouldFailed() throws {
        
    }
}
