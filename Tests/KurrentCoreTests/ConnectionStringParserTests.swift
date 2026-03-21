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
        ("esdb://localhost:2113?tls=false", URLScheme.kurrentdb),
        ("esdb+discover://", URLScheme.dnsDiscover),
        ("esd://", nil),
        ("http://", nil),
        ("https://", nil),
        ("testuri", nil),
    ])
    func testSchemeESDB(connectionString: String, scheme: URLScheme?) async throws {
        let parser = URLSchemeParser()
        let parsedResult = parser.parse(connectionString)

        #expect(parsedResult == scheme)
    }

    @Test("test host should be parsed succeed.", arguments: [
        ("esdb://localhost:2113?tls=false", "localhost"),
        ("esdb://eventstore-service:2113?tls=false", "eventstore-service"),
        ("esdb://eventstore_service:2113?tls=false", "eventstore_service"),
        ("esdb://192.168.41.32:2113?tls=false", "192.168.41.32"),
        ("esdb://192.168:2113?tls=false", nil),
        // RFC 1123: digit-starting labels are valid if they contain at least one letter
        ("esdb://8node.org:2113?tls=false", "8node.org"),
        ("esdb://888node.org:2113?tls=false", "888node.org"),
    ])
    func test(connectionString: String, hostName: String?) throws {
        let parser = EndpointParser()
        let endpoints = try #require(parser.parse(connectionString))

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
        let endpoints = try #require(parser.parse(connectionString))

        let expectedEndpoints = expected.map { Endpoint(host: $0.0, port: $0.1) }
        #expect(endpoints == expectedEndpoints)
    }
}

// MARK: - ClientSettings.parse() integration tests

@Suite("ClientSettings.parse()")
struct ClientSettingsParsingTests {

    // MARK: Cluster Mode

    @Test("single endpoint → standalone mode")
    func testStandaloneMode() throws {
        let settings = try ClientSettings.parse(connectionString: "esdb://localhost:2113?tls=false")
        if case .standalone(let endpoint) = settings.clusterMode {
            #expect(endpoint.host == "localhost")
            #expect(endpoint.port == 2113)
        } else {
            Issue.record("Expected .standalone cluster mode")
        }
    }

    @Test("multiple endpoints → seeds mode")
    func testSeedsMode() throws {
        let settings = try ClientSettings.parse(connectionString: "esdb://node1:2113,node2:2114?tls=false")
        if case .seeds(let endpoints) = settings.clusterMode {
            #expect(endpoints.count == 2)
            #expect(endpoints[0].host == "node1")
            #expect(endpoints[1].host == "node2")
        } else {
            Issue.record("Expected .seeds cluster mode")
        }
    }

    @Test("esdb+discover scheme → dns discover mode")
    func testDNSDiscoverMode() throws {
        let settings = try ClientSettings.parse(connectionString: "esdb+discover://node1.dns.name:2113")
        if case .dns(let domain) = settings.clusterMode {
            #expect(domain.host == "node1.dns.name")
        } else {
            Issue.record("Expected .dns cluster mode")
        }
    }

    // MARK: nodePreference

    @Test("nodePreference is parsed case-insensitively", arguments: zip(
        ["leader", "follower", "random", "readonlyreplica", "Leader", "ReadOnlyReplica"],
        [NodePreference.leader, .follower, .random, .readOnlyReplica, .leader, .readOnlyReplica]
    ))
    func testNodePreference(rawValue: String, expected: NodePreference) throws {
        let settings = try ClientSettings.parse(connectionString: "esdb://localhost:2113?nodepreference=\(rawValue)")
        #expect(settings.nodePreference == expected)
    }

    @Test("nodePreference defaults to .leader when absent")
    func testNodePreferenceDefault() throws {
        let settings = try ClientSettings.parse(connectionString: "esdb://localhost:2113")
        #expect(settings.nodePreference == .leader)
    }

    // MARK: gossipTimeout

    @Test("gossipTimeout is parsed in seconds")
    func testGossipTimeout() throws {
        let settings = try ClientSettings.parse(connectionString: "esdb://localhost:2113?gossiptimeout=10")
        #expect(settings.gossipTimeout == .seconds(10))
    }

    @Test("gossipTimeout defaults to 5s when absent")
    func testGossipTimeoutDefault() throws {
        let settings = try ClientSettings.parse(connectionString: "esdb://localhost:2113")
        #expect(settings.gossipTimeout == .seconds(5))
    }

    // MARK: maxDiscoveryAttempts

    @Test("maxDiscoveryAttempts is parsed as UInt16")
    func testMaxDiscoveryAttempts() throws {
        let settings = try ClientSettings.parse(connectionString: "esdb://localhost:2113?maxdiscoverattempts=5")
        #expect(settings.maxDiscoveryAttempts == 5)
    }

    @Test("maxDiscoveryAttempts defaults to 10 when absent")
    func testMaxDiscoveryAttemptsDefault() throws {
        let settings = try ClientSettings.parse(connectionString: "esdb://localhost:2113")
        #expect(settings.maxDiscoveryAttempts == 10)
    }

    // MARK: discoveryInterval

    @Test("discoveryInterval is parsed in milliseconds")
    func testDiscoveryInterval() throws {
        let settings = try ClientSettings.parse(connectionString: "esdb://localhost:2113?discoveryinterval=500")
        #expect(settings.discoveryInterval == .milliseconds(500))
    }

    @Test("discoveryInterval defaults to 100ms when absent")
    func testDiscoveryIntervalDefault() throws {
        let settings = try ClientSettings.parse(connectionString: "esdb://localhost:2113")
        #expect(settings.discoveryInterval == .milliseconds(100))
    }

    // MARK: keepAlive

    @Test("keepAlive connection string values (seconds) are converted to milliseconds internally")
    func testKeepAlive() throws {
        let settings = try ClientSettings.parse(connectionString: "esdb://localhost:2113?keepaliveinterval=30&keepalivetimeout=60")
        #expect(settings.keepAlive.interval == .milliseconds(30_000))
        #expect(settings.keepAlive.timeout == .milliseconds(60_000))
    }

    @Test("keepAlive uses default when only one of the two params is provided")
    func testKeepAlivePartialParams() throws {
        let settings = try ClientSettings.parse(connectionString: "esdb://localhost:2113?keepaliveinterval=30")
        #expect(settings.keepAlive.interval == KeepAlive.default.interval)
        #expect(settings.keepAlive.timeout == KeepAlive.default.timeout)
    }

    @Test("keepAlive defaults to 10s interval and timeout when absent")
    func testKeepAliveDefault() throws {
        let settings = try ClientSettings.parse(connectionString: "esdb://localhost:2113")
        #expect(settings.keepAlive.interval == .seconds(10))
        #expect(settings.keepAlive.timeout == .seconds(10))
    }

    // MARK: connectionName

    @Test("connectionName is parsed from query string")
    func testConnectionName() throws {
        let settings = try ClientSettings.parse(connectionString: "esdb://localhost:2113?connectionname=myapp")
        #expect(settings.connectionName == "myapp")
    }

    @Test("connectionName is nil when absent")
    func testConnectionNameDefault() throws {
        let settings = try ClientSettings.parse(connectionString: "esdb://localhost:2113")
        #expect(settings.connectionName == nil)
    }

    // MARK: TLS

    @Test("tls flag is parsed as Bool", arguments: [
        ("esdb://localhost:2113?tls=true", true),
        ("esdb://localhost:2113?tls=false", false),
    ])
    func testTLSFlag(connectionString: String, expected: Bool) throws {
        let settings = try ClientSettings.parse(connectionString: connectionString)
        #expect(settings.secure == expected)
    }

    @Test("tls defaults to true when absent")
    func testTLSDefault() throws {
        let settings = try ClientSettings.parse(connectionString: "esdb://localhost:2113")
        #expect(settings.secure == true)
    }

    @Test("tlsverifycert=true enables certificate verification")
    func testTLSVerifyCert() throws {
        let settings = try ClientSettings.parse(connectionString: "esdb://localhost:2113?tls=true&tlsverifycert=true")
        #expect(settings.tlsVerifyCert == true)
    }

    @Test("tlsverifycert defaults to true when absent")
    func testTLSVerifyCertDefault() throws {
        let settings = try ClientSettings.parse(connectionString: "esdb://localhost:2113")
        #expect(settings.tlsVerifyCert == true)
    }

    // MARK: defaultDeadline

    @Test("defaultDeadline is parsed as Int")
    func testDefaultDeadline() throws {
        let settings = try ClientSettings.parse(connectionString: "esdb://localhost:2113?defaultdeadline=5000")
        #expect(settings.defaultDeadline == 5000)
    }

    @Test("defaultDeadline defaults to .max when absent")
    func testDefaultDeadlineDefault() throws {
        let settings = try ClientSettings.parse(connectionString: "esdb://localhost:2113")
        #expect(settings.defaultDeadline == .max)
    }

    // MARK: Authentication

    @Test("basic credentials are parsed from URL authority")
    func testBasicCredentials() throws {
        let settings = try ClientSettings.parse(connectionString: "esdb://admin:changeit@localhost:2113")
        if case .credentials(let username, let password) = settings.authentication {
            #expect(username == "admin")
            #expect(password == "changeit")
        } else {
            Issue.record("Expected .credentials authentication, got \(String(describing: settings.authentication))")
        }
    }

    @Test("no authentication when credentials are absent")
    func testNoAuthentication() throws {
        let settings = try ClientSettings.parse(connectionString: "esdb://localhost:2113")
        #expect(settings.authentication == nil)
    }

    @Test("X.509 authentication is parsed from usercertfile and userkeyfile")
    func testX509Authentication() throws {
        let settings = try ClientSettings.parse(connectionString: "esdb://localhost:2113?usercertfile=/path/to/cert.pem&userkeyfile=/path/to/key.pem")
        if case .x509(let certFile, let keyFile) = settings.authentication {
            #expect(certFile == "/path/to/cert.pem")
            #expect(keyFile == "/path/to/key.pem")
        } else {
            Issue.record("Expected .x509 authentication, got \(String(describing: settings.authentication))")
        }
    }

    @Test("X.509 takes priority over URL credentials when both are present")
    func testX509TakesPriorityOverCredentials() throws {
        let settings = try ClientSettings.parse(connectionString: "esdb://admin:changeit@localhost:2113?usercertfile=/cert.pem&userkeyfile=/key.pem")
        if case .x509 = settings.authentication {
            // correct: X.509 wins
        } else {
            Issue.record("Expected X.509 to take priority over basic credentials")
        }
    }

    // MARK: query params with '@' in value don't corrupt credential parsing

    @Test("query param value containing '@' does not break credential parsing")
    func testAtSignInQueryParam() throws {
        let settings = try ClientSettings.parse(connectionString: "esdb://admin:changeit@localhost:2113?connectionname=user@domain")
        if case .credentials(let username, _) = settings.authentication {
            #expect(username == "admin")
        } else {
            Issue.record("Expected .credentials authentication")
        }
        #expect(settings.connectionName == "user@domain")
    }

    // MARK: Error cases

    @Test("invalid scheme throws")
    func testInvalidScheme() {
        #expect(throws: KurrentError.self) {
            try ClientSettings.parse(connectionString: "http://localhost:2113")
        }
    }

    @Test("missing host throws")
    func testMissingHost() {
        #expect(throws: KurrentError.self) {
            try ClientSettings.parse(connectionString: "esdb://")
        }
    }
}
