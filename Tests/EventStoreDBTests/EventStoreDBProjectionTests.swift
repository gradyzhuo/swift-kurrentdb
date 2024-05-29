//
//  EventStoreDBProjectionTests.swift
//
//
//  Created by Grady Zhuo on 2023/12/5.
//

@testable import EventStoreDB
import SwiftProtobuf
import XCTest

final class EventStoreDBProjectionTests: XCTestCase {
    override func setUp() async throws {
        // await EventStoreDB.using(settings: .localhost(port: 2111, userCredentials: .init(username: "admin", password: "changeit"), trustRoots: .crtInBundle("ca", inBundle: .module)))
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testCreate() async throws {
//        let projection = try Projections(mode: .continuous(name: "test", emitEnable: true, trackEmittedStreams: true))
//        let x: String? = try await projection.getState { options in
//            options.partition("xxx")
//        }

//        let client = try ProjectionsClient(mode: .continuous(name: "projectionTesting", emitEnable: true, trackEmittedStreams: false))
//
    }
}
