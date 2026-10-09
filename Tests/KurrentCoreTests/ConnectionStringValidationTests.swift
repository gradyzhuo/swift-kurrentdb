//
//  ConnectionStringValidationTests.swift
//  KurrentCoreTests
//
//  What ClientSettings.parse(connectionString:) does with the parameters, and the regressions
//  behind the rewrite (security review 2026-10-04, S01 and S03): characters in a password must
//  never change settings, and no input may trap.
//

@testable import KurrentDB
import Testing

@Suite("Connection string validation")
struct ConnectionStringValidationTests {
    private func parseReason(_ input: String) -> String? {
        do throws(KurrentError) {
            _ = try ClientSettings.parse(connectionString: input)
            return nil
        } catch {
            if case let .internalParsingError(reason) = error { return reason }
            return "\(error)"
        }
    }

    private func password(_ settings: ClientSettings) -> String? {
        if case let .credentials(_, password) = settings.authentication { return password }
        return nil
    }

    // MARK: S01 — characters in the password never change settings

    @Test("'&tls=false' inside the password stays in the password and TLS stays on")
    func ampersandInPasswordDoesNotDisableTLS() throws {
        let settings = try ClientSettings.parse(connectionString: "esdb://admin:pa&tls=false&x=y@db.example.com:2113")
        #expect(settings.secure == true)
        #expect(password(settings) == "pa&tls=false&x=y")
    }

    @Test("An unencoded '@' in the password is rejected and the reason says how to fix it")
    func unencodedAtInPassword() {
        let message = parseReason("esdb://admin:p@ss@db.example.com:2113")
        #expect(message != nil)
        #expect(message?.contains("%40") == true)
        #expect(message?.contains("p@ss") == false)
    }

    @Test("An encoded '@' in the password parses")
    func encodedAtInPassword() throws {
        let settings = try ClientSettings.parse(connectionString: "esdb://admin:p%40ss@db.example.com:2113")
        #expect(password(settings) == "p@ss")
        #expect(settings.endpoints == [Endpoint(host: "db.example.com", port: 2113)])
    }

    @Test("S01 residual: an unencoded '@' in a query value cannot turn the host into credentials")
    func atInQueryValueResidual() {
        let message = parseReason("esdb://admin:2113?tls=false&connectionName=x@db.example.com")
        #expect(message?.contains("%40") == true)
        #expect(message?.contains("ClientSettings.authenticated(.credentials(username:password:))") == true)
    }

    @Test("A ':' in the password stays in the password")
    func colonInPassword() throws {
        let settings = try ClientSettings.parse(connectionString: "esdb://admin:p:ss@db.example.com:2113")
        guard case let .credentials(username, password) = settings.authentication else {
            Issue.record("expected credentials")
            return
        }
        #expect(username == "admin")
        #expect(password == "p:ss")
    }

    @Test("A percent-encoded password is decoded")
    func percentEncodedPassword() throws {
        let settings = try ClientSettings.parse(connectionString: "esdb://admin:p%26ss@db.example.com:2113")
        #expect(password(settings) == "p&ss")
    }

    @Test("A query value with ':' and an encoded '@' does not invent credentials")
    func queryDoesNotInventCredentials() throws {
        let settings = try ClientSettings.parse(connectionString: "esdb://db.example.com:2113?connectionName=svc:a%40b")
        #expect(settings.authentication == nil)
        #expect(settings.connectionName == "svc:a@b")
    }

    // MARK: S03 — no trap

    @Test("Duplicate parameters differing only in case are an error, not a trap")
    func duplicateParameters() {
        #expect(parseReason("esdb://localhost:2113?tls=true&TLS=false") != nil)
    }

    @Test("keepAlive values that overflow are an error, not a trap")
    func keepAliveOverflow() {
        #expect(parseReason("esdb://localhost:2113?keepAliveInterval=18446744073709551615&keepAliveTimeout=1") != nil)
        #expect(parseReason("esdb://localhost:2113?keepAliveInterval=9223372037&keepAliveTimeout=1") != nil)
    }

    @Test("Durations whose nanoseconds overflow Int64 are an error", arguments: [
        "esdb://localhost?gossipTimeout=9223372037",
        "esdb://localhost?discoveryInterval=9223372036855",
        "esdb://localhost?defaultDeadline=9223372036855",
    ])
    func durationOverflow(input: String) {
        #expect(parseReason(input) != nil)
    }

    @Test("defaultDeadline at the largest representable millisecond value parses exactly")
    func defaultDeadlineAtLimit() throws {
        let settings = try ClientSettings.parse(connectionString: "esdb://localhost?defaultDeadline=9223372036854")
        #expect(settings.defaultDeadline == 9_223_372_036_854)
    }

    @Test("Durations at the largest representable value are accepted")
    func durationAtLimit() throws {
        let settings = try ClientSettings.parse(connectionString: "esdb://localhost?gossipTimeout=9223372036&keepAliveInterval=9223372036&keepAliveTimeout=9223372036")
        #expect(settings.gossipTimeout == .seconds(9_223_372_036))
        #expect(settings.keepAlive.interval == .seconds(9_223_372_036))
    }

    @Test("No input makes parse trap")
    func noInputTraps() {
        var generator = SplitMix64(seed: 0x5EED_C0DE)
        let alphabet = Array("esdbkurentdisvoc+:/@?#&=%,.-_0123456789aAfFzZ ~密\u{0}\n\t[]")
        let prefixes = ["", "esdb://", "kurrentdb+discover://", "esdb://admin:pw@", "esdb://localhost:2113?", "esdb://localhost?keepAliveInterval="]
        for _ in 0 ..< 10_000 {
            var input = prefixes.randomElement(using: &generator)!
            for _ in 0 ..< Int.random(in: 0 ... 40, using: &generator) {
                input.append(alphabet.randomElement(using: &generator)!)
            }
            // A trap would terminate the test process; a thrown KurrentError is fine.
            _ = try? ClientSettings.parse(connectionString: input)
        }
    }

    // MARK: Strict character rules (.rfc3986)

    @Test("Leading and trailing whitespace and newlines are ignored", arguments: [
        "\nesdb://admin:pw@localhost:2113\n",
        "esdb://admin:pw@localhost:2113\r\n",
        "  esdb://admin:pw@localhost:2113  ",
        "\t esdb://admin:pw@localhost:2113 \n\n",
    ])
    func surroundingWhitespaceIgnored(input: String) throws {
        let settings = try ClientSettings.parse(connectionString: input)
        #expect(password(settings) == "pw")
        #expect(settings.endpoints == [Endpoint(host: "localhost", port: 2113)])
    }

    @Test("Interior whitespace is rejected", arguments: [
        "esdb://adm in:pw@localhost:2113",
        "esdb://admin:p w@localhost:2113",
        "esdb://local host:2113",
        "esdb://localhost:2113?connectionName=a b",
        "esdb://localhost:2113? tls=false",
        "esdb://localhost:2113?tls=false\n&connectionName=x",
    ])
    func interiorWhitespaceRejected(input: String) {
        #expect(parseReason(input) != nil)
    }

    @Test("Raw non-ASCII and control characters are rejected in credentials and values", arguments: [
        "esdb://admin:密@localhost:2113",
        "esdb://admin:p\u{01}w@localhost:2113",
        "esdb://admin:p\u{7F}w@localhost:2113",
        "esdb://localhost:2113?connectionName=密",
        "esdb://localhost:2113?connectionName=a\u{01}b",
        "esdb://localhost:2113?connectionName=a\"b",
        "esdb://admin:p{w@localhost:2113",
        "esdb://admin:p\\w@localhost:2113",
        "esdb://admin:p^w@localhost:2113",
        "esdb://localhost:2113?connectionName=a|b",
        "esdb://localhost:2113?connectionName=a\u{0301}",
        "esdb://admin:pw@localhost:2113?tls=false&\u{0301}=1",
    ])
    func rawBytesRejected(input: String) {
        #expect(parseReason(input) != nil)
    }

    @Test("Raw characters RFC 3986 allows are accepted in credentials and values")
    func allowedRawCharacters() throws {
        let settings = try ClientSettings.parse(connectionString: "esdb://us.er-_~:!$&'()*+,;=:x@localhost:2113?connectionName=a/b?c:d,e;f=g~h")
        #expect(password(settings) == "!$&'()*+,;=:x")
        #expect(settings.connectionName == "a/b?c:d,e;f=g~h")
    }

    @Test("IPv6 literals are rejected with an explicit reason", arguments: ["esdb://[::1]:2113", "esdb://[::1]", "esdb://node1:2113,[::1]:2113"])
    func ipv6Rejected(input: String) {
        #expect(parseReason(input)?.contains("IPv6") == true)
    }

    @Test("A host name with one trailing dot parses and is kept as written")
    func trailingDotHost() throws {
        let settings = try ClientSettings.parse(connectionString: "esdb://node.svc.cluster.local.:2113")
        #expect(settings.endpoints == [Endpoint(host: "node.svc.cluster.local.", port: 2113)])
        #expect(parseReason("esdb://node..:2113") != nil)
        #expect(parseReason("esdb://.:2113") != nil)
    }

    @Test("Echoed key names are escaped and capped")
    func keyEscaping() {
        let escaped = parseReason("esdb://localhost?%0Ax=1")
        #expect(escaped?.contains("\\u{0A}") == true)
        #expect(escaped?.contains("\n") == false)

        let key = String(repeating: "k", count: 200)
        let long = parseReason("esdb://localhost?\(key)=1")
        #expect(long != nil)
        #expect(long?.contains(String(repeating: "k", count: 64) + "…") == true)
        #expect(long?.contains(String(repeating: "k", count: 65)) == false)

        let duplicate = parseReason("esdb://localhost?%0Ax=1&%0Ax=2")
        #expect(duplicate?.contains("\\u{0A}") == true)
        #expect(duplicate?.contains("\n") == false)
    }

    @Test("The explicit .rfc3986 policy equals the default")
    func explicitPolicyEqualsDefault() throws {
        let input = "esdb://admin:p%40ss@localhost:2113?tls=false&connectionName=x"
        let explicit = try ClientSettings.parse(connectionString: input, policy: .rfc3986)
        let implicit = try ClientSettings.parse(connectionString: input)
        #expect(explicit.endpoints == implicit.endpoints)
        #expect(explicit.secure == implicit.secure)
        #expect(explicit.connectionName == implicit.connectionName)
        #expect(password(explicit) == password(implicit))
        #expect(RFC3986Policy.rfc3986 == RFC3986Policy())
    }

    @Test("fromEnv(key:policy:) accepts .rfc3986 and reports an unset variable")
    func fromEnvAcceptsPolicy() {
        #expect(parseReasonEnv("KURRENTDB_TEST_DEFINITELY_UNSET_VARIABLE") != nil)
    }

    private func parseReasonEnv(_ key: String) -> String? {
        do throws(KurrentError) {
            _ = try ClientSettings.fromEnv(key: key, policy: .rfc3986)
            return nil
        } catch {
            if case let .internalParsingError(reason) = error { return reason }
            return "\(error)"
        }
    }

    // MARK: Parameter values

    @Test("Boolean values are case-insensitive")
    func booleanValuesAreCaseInsensitive() throws {
        let settings = try ClientSettings.parse(connectionString: "ESDB://localhost:2113?TLS=FALSE&TlsVerifyCert=False")
        #expect(settings.secure == false)
        #expect(settings.tlsVerifyCert == false)
    }

    @Test("Malformed values are errors that name the parameter but not the value", arguments: [
        ("esdb://localhost?tls=s3cr3t", "tls"),
        ("esdb://localhost?tlsVerifyCert=s3cr3t", "tlsverifycert"),
        ("esdb://localhost?nodePreference=s3cr3t", "nodepreference"),
        ("esdb://localhost?gossipTimeout=s3cr3t", "gossiptimeout"),
        ("esdb://localhost?gossipTimeout=0", "gossiptimeout"),
        ("esdb://localhost?gossipTimeout=-1", "gossiptimeout"),
        ("esdb://localhost?maxDiscoverAttempts=70000", "maxdiscoverattempts"),
        ("esdb://localhost?maxDiscoverAttempts=0", "maxdiscoverattempts"),
        ("esdb://localhost?discoveryInterval=s3cr3t", "discoveryinterval"),
        ("esdb://localhost?defaultDeadline=0", "defaultdeadline"),
        ("esdb://localhost?keepAliveInterval=s3cr3t&keepAliveTimeout=1", "keepaliveinterval"),
        ("esdb://localhost?connectionName=", "connectionname"),
        ("esdb://localhost?tlsCaFile=", "tlscafile"),
    ])
    func malformedValues(input: String, parameter: String) {
        let message = parseReason(input)
        #expect(message?.contains(parameter) == true)
        #expect(message?.contains("s3cr3t") == false)
    }

    @Test("An unknown parameter is an error that names it")
    func unknownParameter() {
        let message = parseReason("esdb://localhost?tlsVerifyCrt=false")
        #expect(message?.contains("tlsverifycrt") == true)
    }

    @Test("Only one of userCertFile / userKeyFile is an error")
    func halfX509() {
        #expect(parseReason("esdb://localhost?userCertFile=/cert.pem") != nil)
        #expect(parseReason("esdb://localhost?userKeyFile=/key.pem") != nil)
    }
}

/// Deterministic generator so the sweep is reproducible.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
