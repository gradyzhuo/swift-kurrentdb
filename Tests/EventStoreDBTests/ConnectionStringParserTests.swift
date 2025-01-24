//
//  ConnectionStringParserTests.swift
//
//
//  Created by Grady Zhuo on 2024/5/25.
//

@testable import KurrentCore
import Foundation
import XCTest
@testable import EventStoreDB

final class ConnectionStringParserTests: XCTestCase {
    func test_scheme_should_be_esdb_explicitly() throws {
        let connectionString = "esdb://"

        let parser = SchemeParser()
        let parsedResult = try parser.parse(connectionString)

        XCTAssertEqual(parsedResult, ClientSettings.ValidScheme.esdb)
    }

    func test_scheme_should_not_be_esdb() throws {
        let connectionStrings = [
            "esd://",
            "http://",
            "https://",
            "testuri",
        ]

        let parser = SchemeParser()

        for connectionString in connectionStrings {
            let parsedResult = try parser.parse(connectionString)
            XCTAssertNil(parsedResult)
        }
    }

    func test_host_should_be_parsed_localhost_succeed() throws {
        let connectionString = "esdb://localhost:2113?tls=false"

        let parser = EndpointParser()
        let endpoints = try parser.parse(connectionString)

        XCTAssertEqual(endpoints?.count, 1)
        XCTAssertEqual(endpoints?[0].host, "localhost")
    }
    
    func test_host_should_be_parsed_host_contains_dash_succeed() throws {
        let connectionString = "esdb://eventstore-service:2113?tls=false"

        let parser = EndpointParser()
        let endpoints = try parser.parse(connectionString)

        XCTAssertEqual(endpoints?.count, 1)
        XCTAssertEqual(endpoints?[0].host, "eventstore-service")
    }

    func test_host_should_be_parsed_ip_succeed() throws {
        let connectionString = "esdb://192.168.41.32:2113?tls=false"

        let parser = EndpointParser()
        let endpoints = try parser.parse(connectionString)

        XCTAssertEqual(endpoints?.count, 1)
        XCTAssertEqual(endpoints?[0].host, "192.168.41.32")
    }

    func test_host_should_be_parsed_ip_failed() throws {
        let connectionString = "esdb://192.168:2113?tls=false"

        let parser = EndpointParser()
        let endpoints = try parser.parse(connectionString)

        XCTAssertEqual(endpoints?.count, 0)
    }
}
