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

    @Test("An unencoded '@' in the password parses")
    func unencodedAtInPassword() throws {
        let settings = try ClientSettings.parse(connectionString: "esdb://admin:p@ss@db.example.com:2113")
        #expect(password(settings) == "p@ss")
        #expect(settings.endpoints == [Endpoint(host: "db.example.com", port: 2113)])
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

    @Test("A query value with ':' and '@' does not invent credentials")
    func queryDoesNotInventCredentials() throws {
        let settings = try ClientSettings.parse(connectionString: "esdb://db.example.com:2113?connectionName=svc:a@b")
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

    @Test("Durations at the largest representable value are accepted")
    func durationAtLimit() throws {
        let settings = try ClientSettings.parse(connectionString: "esdb://localhost?gossipTimeout=9223372036&keepAliveInterval=9223372036&keepAliveTimeout=9223372036")
        #expect(settings.gossipTimeout == .seconds(9_223_372_036))
        #expect(settings.keepAlive.interval == .seconds(9_223_372_036))
    }

    @Test("No input makes parse trap")
    func noInputTraps() {
        var generator = SplitMix64(seed: 0x5EED_C0DE)
        let alphabet = Array("esdbkurentdisvoc+:/@?#&=%,.-_0123456789aAfFzZ ~密\u{0}")
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
