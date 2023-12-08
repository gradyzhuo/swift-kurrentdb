//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/12/5.
//

import XCTest
@testable import EventStoreDB
import SwiftProtobuf

final class EventStoreDBProjectionTests: XCTestCase {
    
    override func setUpWithError() throws {
        
        
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func testState() async throws{
        
//        let projection = try Projections(mode: .continuous(name: "test", emitEnable: true, trackEmittedStreams: true))
//        let x: String? = try await projection.getState { options in
//            options.partition("xxx")
//        }
        
    }
    
}
