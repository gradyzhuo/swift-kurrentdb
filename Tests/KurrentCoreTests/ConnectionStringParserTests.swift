//
//  ConnectionStringParserTests.swift
//
//
//  Created by Grady Zhuo on 2024/5/25.
//

@testable import KurrentDB
import Testing

@Suite("ConnectionStringParser")
struct ConnectionStringParser {
    @Test("Test scheme of url should be esdb explicitly", arguments: [
        ("esdb://localhost:2113?tls=false", URLScheme.esdb),
        ("esdb+discover://", URLScheme.dnsDiscover),
        ("esd://", nil),
        ("http://", nil),
        ("https://", nil),
        ("testuri", nil),
    ])
    func testSchemeESDB(connectionString: String, scheme: URLScheme?) async throws {
        let parser = URLSchemeParser()
        let parsedResult = try parser.parse(connectionString)

        #expect(parsedResult == scheme)
    }

    @Test("test host should be parsed succeed.", arguments: [
        ("esdb://localhost:2113?tls=false", "localhost"),
        ("esdb://eventstore-service:2113?tls=false", "eventstore-service"),
        ("esdb://eventstore_service:2113?tls=false", "eventstore_service"),
        ("esdb://192.168.41.32:2113?tls=false", "192.168.41.32"),
        ("esdb://192.168:2113?tls=false", nil),
    ])
    func test(connectionString: String, hostName: String?) throws {
        let parser = EndpointParser()
        let endpoints = try #require(try parser.parse(connectionString))

        if endpoints.count > 0 {
            #expect(endpoints[0].host == hostName)
        }
    }
    
    @Test("test host should be parsed succeed.", arguments: [
        ("esdb+discover://admin:changeit@node1.dns.name:2113,node2.dns.name:2114,node3.dns.name:2115", [
            ("node1.dns.name", 2113),
            ("node2.dns.name", 2114),
            ("node3.dns.name", 2115),
        ]),
    ])
    func test(connectionString: String, expected: [(String, UInt32)]) throws {
        let parser = EndpointParser()
        let endpoints = try #require(try parser.parse(connectionString))

        let expectedEndpoints = expected.map{ Endpoint(host: $0.0, port: $0.1) }
        #expect(endpoints == expectedEndpoints)
    }
}
