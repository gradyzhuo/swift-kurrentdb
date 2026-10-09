//
//  ConnectionStringTests.swift
//  KurrentCoreTests
//
//  Structural parsing only: how a connection string is split into scheme, credentials, hosts and
//  query parameters. Parameter meaning and validation are covered by ConnectionStringValidationTests.
//

@testable import KurrentDB
import Testing

@Suite("ConnectionString")
struct ConnectionStringTests {
    private func reason(_ body: () throws(KurrentError) -> Void) -> String? {
        do throws(KurrentError) {
            try body()
            return nil
        } catch {
            if case let .internalParsingError(reason) = error { return reason }
            return "\(error)"
        }
    }

    // MARK: Scheme

    @Test("Every accepted scheme maps to its URLScheme", arguments: [
        ("esdb://localhost", URLScheme.kurrentdb),
        ("kurrentdb://localhost", .kurrentdb),
        ("kurrent://localhost", .kurrentdb),
        ("kdb://localhost", .kurrentdb),
        ("esdb+discover://localhost", .dnsDiscover),
        ("kurrentdb+discover://localhost", .dnsDiscover),
    ])
    func schemes(input: String, expected: URLScheme) throws {
        #expect(try ConnectionString(parsing: input).scheme == expected)
    }

    @Test("Scheme is case-insensitive")
    func schemeIsCaseInsensitive() throws {
        #expect(try ConnectionString(parsing: "ESDB://localhost").scheme == .kurrentdb)
        #expect(try ConnectionString(parsing: "KurrentDB+Discover://localhost").scheme == .dnsDiscover)
    }

    @Test("Unknown or missing schemes are rejected", arguments: ["http://localhost", "esd://localhost", "localhost:2113", "testuri", ""])
    func badSchemes(input: String) {
        #expect(reason { () throws(KurrentError) in _ = try ConnectionString(parsing: input) } != nil)
    }

    @Test("Schemes with non-ASCII or non-RFC 3986 bytes are rejected before lowercasing", arguments: [
        "\u{212A}db://localhost:2113", "ésdb://localhost", "+esdb://localhost",
    ])
    func nonAsciiSchemesRejected(input: String) {
        #expect(reason { () throws(KurrentError) in _ = try ConnectionString(parsing: input) } != nil)
    }

    // MARK: Hosts

    @Test("Numeric hosts a resolver would reinterpret are rejected", arguments: [
        "010.0.0.1", "1.2.3.04", "00.0.0.1", "0x7f.0.0.1", "0X7F.0.0.1", "0x7f000001", "127.1",
    ])
    func reinterpretableNumericHosts(host: String) {
        #expect(reason { () throws(KurrentError) in _ = try ConnectionString(parsing: "esdb://\(host):2113") } != nil)
    }

    @Test("Strict dotted-quads and names with an ordinary label are accepted", arguments: [
        "0.0.0.0", "10.0.0.1", "255.255.255.255", "0x7f.example.com", "8node.org",
    ])
    func acceptedHosts(host: String) throws {
        #expect(try ConnectionString(parsing: "esdb://\(host):2113").endpoints == [Endpoint(host: host, port: 2113)])
    }

    @Test("Hosts and ports", arguments: [
        ("esdb://localhost:2113", [Endpoint(host: "localhost", port: 2113)]),
        ("esdb://localhost", [Endpoint(host: "localhost", port: 2113)]),
        ("esdb://eventstore-service:2113", [Endpoint(host: "eventstore-service", port: 2113)]),
        ("esdb://eventstore_service:2113", [Endpoint(host: "eventstore_service", port: 2113)]),
        ("esdb://192.168.41.32:2113", [Endpoint(host: "192.168.41.32", port: 2113)]),
        ("esdb://8node.org:2113", [Endpoint(host: "8node.org", port: 2113)]),
        ("esdb://888node.org:2113", [Endpoint(host: "888node.org", port: 2113)]),
        ("esdb+discover://admin:changeit@node1.dns.name:2113,node2.dns.name:2114,node3.dns.name:2115", [
            Endpoint(host: "node1.dns.name", port: 2113),
            Endpoint(host: "node2.dns.name", port: 2114),
            Endpoint(host: "node3.dns.name", port: 2115),
        ]),
    ])
    func hosts(input: String, expected: [Endpoint]) throws {
        #expect(try ConnectionString(parsing: input).endpoints == expected)
    }

    @Test("Malformed hosts and ports are rejected", arguments: [
        "esdb://",
        "esdb://?tls=false",
        "esdb://192.168:2113",
        "esdb://1.2.3.256:2113",
        "esdb://localhost:",
        "esdb://localhost:0",
        "esdb://localhost:65536",
        "esdb://localhost:99999999999999999999",
        "esdb://localhost:21a3",
        "esdb://node1:2113,,node2:2113",
        "esdb://node1:2113,",
        "esdb://local host:2113",
        "esdb://local%68ost:2113",
        "esdb://.localhost:2113",
        "esdb://a:b:2113",
    ])
    func badHosts(input: String) {
        #expect(reason { () throws(KurrentError) in _ = try ConnectionString(parsing: input) } != nil)
    }

    // MARK: Credentials

    @Test("Credentials split at the '@' and the first ':' and are percent-decoded", arguments: [
        ("esdb://admin:changeit@localhost", "admin", "changeit"),
        ("esdb://admin:p:ss@localhost", "admin", "p:ss"),
        ("esdb://admin:pa&tls=false&x=y@localhost", "admin", "pa&tls=false&x=y"),
        ("esdb://admin:p%40ss@localhost", "admin", "p@ss"),
        ("esdb://admin:p%26ss@localhost", "admin", "p&ss"),
        ("esdb://admin:p%40ss%2F%3F%23%25@localhost", "admin", "p@ss/?#%"),
        ("esdb://ad%3Amin:x@localhost", "ad:min", "x"),
        ("esdb://admin:%E5%AF%86@localhost", "admin", "密"),
        ("esdb://admin:@localhost", "admin", ""),
    ])
    func credentials(input: String, username: String, password: String) throws {
        let parsed = try ConnectionString(parsing: input)
        #expect(parsed.credentials == .init(username: username, password: password))
        #expect(parsed.endpoints == [Endpoint(host: "localhost", port: 2113)])
        #expect(parsed.parameters.isEmpty)
    }

    @Test("A percent-encoded '@' in a query value is decoded and is not credentials")
    func encodedAtInQueryIsNotCredentials() throws {
        let parsed = try ConnectionString(parsing: "esdb://db.example.com:2113?connectionName=svc:a%40b")
        #expect(parsed.credentials == nil)
        #expect(parsed.endpoints == [Endpoint(host: "db.example.com", port: 2113)])
        #expect(parsed.parameters == ["connectionname": "svc:a@b"])
    }

    @Test("An unencoded '@' in the credentials or the query is rejected", arguments: [
        "esdb://admin:p@ss@localhost",
        "esdb://a@b:c@localhost",
        "esdb://db.example.com:2113?connectionName=svc:a@b",
        "esdb://admin:2113?tls=false&connectionName=x@db.example.com",
    ])
    func unencodedAtIsRejected(input: String) {
        #expect(reason { () throws(KurrentError) in _ = try ConnectionString(parsing: input) } != nil)
    }

    @Test("Malformed credentials are rejected", arguments: [
        "esdb://admin@localhost",
        "esdb://:pw@localhost",
        "esdb://admin:p%zz@localhost",
        "esdb://admin:p%4@localhost",
        "esdb://admin:%FF@localhost",
    ])
    func badCredentials(input: String) {
        #expect(reason { () throws(KurrentError) in _ = try ConnectionString(parsing: input) } != nil)
    }

    @Test("An unencoded '/', '?' or '#' in the password cannot be mistaken for structure", arguments: [
        "esdb://admin:pa?tls=false@db.example.com:2113",
        "esdb://admin:pa/x@db.example.com:2113",
        "esdb://admin:p#ss@db.example.com:2113",
    ])
    func unencodedDelimitersInPasswordFail(input: String) {
        #expect(reason { () throws(KurrentError) in _ = try ConnectionString(parsing: input) } != nil)
    }

    // MARK: Query

    @Test("Parameter keys are lower-cased; values are percent-decoded and keep their case")
    func parameters() throws {
        let parsed = try ConnectionString(parsing: "esdb://localhost:2113?TLS=False&connectionName=My%20App&tlsCaFile=/certs/ca+1.crt")
        #expect(parsed.parameters == ["tls": "False", "connectionname": "My App", "tlscafile": "/certs/ca+1.crt"])
    }

    @Test("A value keeps every '=' after the first")
    func valueKeepsLaterEquals() throws {
        #expect(try ConnectionString(parsing: "esdb://localhost?connectionName=a=b").parameters == ["connectionname": "a=b"])
    }

    @Test("Empty query segments are ignored", arguments: [
        ("esdb://localhost?", [String: String]()),
        ("esdb://localhost?&", [:]),
        ("esdb://localhost?tls=false&", ["tls": "false"]),
        ("esdb://localhost/?tls=false", ["tls": "false"]),
        ("esdb://localhost?&&tls=false&&", ["tls": "false"]),
    ])
    func emptyQuerySegmentsIgnored(input: String, expected: [String: String]) throws {
        #expect(try ConnectionString(parsing: input).parameters == expected)
    }

    @Test("Duplicate keys are rejected regardless of case, and the error names the key, not the value")
    func duplicateKeys() {
        let message = reason { () throws(KurrentError) in _ = try ConnectionString(parsing: "esdb://localhost?tls=true&TLS=s3cr3t") }
        #expect(message?.contains("tls") == true)
        #expect(message?.contains("s3cr3t") == false)
    }

    @Test("Query errors name the parameter and never echo the value", arguments: [
        ("esdb://localhost?tls=false&connectionName=a b", "a b"),
        ("esdb://localhost?connectionName=user@domain", "user@domain"),
    ])
    func queryErrorsNameParameter(input: String, value: String) {
        let message = reason { () throws(KurrentError) in _ = try ConnectionString(parsing: input) }
        #expect(message?.contains("connectionName") == true)
        #expect(message?.contains(value) == false)
    }

    @Test("A combining mark after '=' or '&' neither hides the separator nor leaks the value")
    func combiningMarksDoNotLeak() {
        let a = reason { () throws(KurrentError) in _ = try ConnectionString(parsing: "esdb://localhost?connectionName=\u{0301}s3cr3t") }
        #expect(a != nil)
        #expect(a?.contains("s3cr3t") == false)
        let b = reason { () throws(KurrentError) in _ = try ConnectionString(parsing: "esdb://localhost?tls=false&connectionName=a\u{0301}b") }
        #expect(b?.contains("connectionName") == true)
        #expect(b?.contains("a\u{0301}b") == false)
        let c = reason { () throws(KurrentError) in _ = try ConnectionString(parsing: "esdb://localhost?tls=false&\u{0301}connectionName=s3cr3t") }
        #expect(c != nil)
        #expect(c?.contains("s3cr3t") == false)
    }

    @Test("Malformed parameter names are named in the reason")
    func malformedNamesAreNamed() {
        let a = reason { () throws(KurrentError) in _ = try ConnectionString(parsing: "esdb://localhost?t%zzls=true") }
        #expect(a?.contains("t%zzls") == true)
        #expect(a?.contains("percent-encoding") == true)
        let b = reason { () throws(KurrentError) in _ = try ConnectionString(parsing: "esdb://localhost?tls VerifyCert=false") }
        #expect(b?.contains("tls VerifyCert") == true)
        #expect(b?.contains("false") == false)
    }

    @Test("An item without '=' names the parameter")
    func itemWithoutEqualsNamesParameter() {
        let message = reason { () throws(KurrentError) in _ = try ConnectionString(parsing: "esdb://localhost?tls") }
        #expect(message?.contains("tls") == true)
    }

    @Test("Malformed query items are rejected", arguments: [
        "esdb://localhost?tls",
        "esdb://localhost?=x",
        "esdb://localhost?tls=%zz",
        "esdb://localhost?t%zzls=true",
    ])
    func badQueryItems(input: String) {
        #expect(reason { () throws(KurrentError) in _ = try ConnectionString(parsing: input) } != nil)
    }

    @Test("A path after the hosts is rejected; a lone '/' is fine")
    func pathIsRejected() throws {
        #expect(reason { () throws(KurrentError) in _ = try ConnectionString(parsing: "esdb://localhost:2113/foo") } != nil)
        #expect(reason { () throws(KurrentError) in _ = try ConnectionString(parsing: "esdb://localhost:2113/foo?tls=false") } != nil)
        #expect(try ConnectionString(parsing: "esdb://localhost:2113/").endpoints.count == 1)
    }

    @Test("A fragment is rejected")
    func fragmentIsRejected() {
        #expect(reason { () throws(KurrentError) in _ = try ConnectionString(parsing: "esdb://localhost:2113?tls=false#x") } != nil)
    }

    @Test("Errors never echo the password")
    func errorsDoNotEchoPassword() {
        for input in ["esdb://admin:s3cr3t-pw@:2113", "esdb://admin:s3cr3t-pw%zz@localhost", "esdb://admin:s3cr3t-pw@localhost:99999", "esdb://admin:s3cr3t-pw@localhost/path"] {
            let message = reason { () throws(KurrentError) in _ = try ConnectionString(parsing: input) }
            #expect(message != nil)
            #expect(message?.contains("s3cr3t") == false)
        }
    }
}
