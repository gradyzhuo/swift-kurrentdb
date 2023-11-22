//
//  EventStoreDBStreamTests.swift
//  
//
//  Created by Ospark.org on 2023/10/28.
//

import XCTest
@testable import EventStoreDB
import GRPC
import NIO

final class EventStoreDBStreamTests: XCTestCase {
    var stream: EventStoreDB.Stream?
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
//        let group = PlatformSupport.makeEventLoopGroup(loopCount: 1)
//        let channel = try GRPCChannelPool.with(
//            target: .hostAndPort("localhost", 2113),
//            transportSecurity: .plaintext,
//            eventLoopGroup: group
//        )
//        
//        stream = try Stream(identifier: "hello-world")
        
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func testAppendEvent() async throws{
//        let response = try await stream?.append(event: .init(type: "test", content: .codable(["other":"test"])))
//            .expected(revision: .any)
//            .perform()
//        switch response {
//        case .success(let value):
//            switch value.position {
//        }
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
