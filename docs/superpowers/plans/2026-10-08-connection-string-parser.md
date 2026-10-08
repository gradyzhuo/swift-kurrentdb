# Connection String Parser Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the four regex connection-string parsers with one RFC 3986–structured parser so that credentials, hosts and query parameters can no longer bleed into each other, percent-encoding works, and no input can trap the process.

**Architecture:** A new value type `ConnectionString` splits the input in a fixed order (scheme → authority → userinfo / hosts → query), percent-decodes userinfo and query, and validates host syntax. `ClientSettings.parse(connectionString:)` only maps `ConnectionString.parameters` to settings, rejecting unknown keys, duplicate keys, malformed values and durations whose nanosecond value would overflow `Int64`. The old parser classes are deleted.

**Tech Stack:** Swift 6.0+ (stdlib `String(validating:as:)`), Swift Testing, no new dependencies.

**Spec:** `docs/superpowers/specs/2026-10-08-connection-string-parser-design.md` (decisions in §7: unknown key → error; literal `%` → RFC percent-decoding).

## Global Constraints

- Public API unchanged: `ClientSettings.parse(connectionString:)`, `ClientSettings.fromEnv(key:)`, `init(stringLiteral:)` keep their signatures.
- Every failure is `KurrentError.internalParsingError(reason:)`. Do not add `KurrentError` cases.
- Error reasons name the field or parameter, never the value, the password, or the raw connection string.
- No input may trap. No `Dictionary(uniqueKeysWithValues:)`, no unchecked arithmetic, no trapping integer initialisers on input.
- All `//` and `///` comments in English.
- Swift 6.0 is the floor (CI runs 6.0–6.4, macOS and Linux). `String(validating:as:)` is available on the package's minimum platforms (macOS 15 / iOS 18).
- Commit subjects `[TAG] message`; **no `Co-Authored-By:` lines** (CLAUDE.local.md).
- Stage explicit paths only; the working tree holds untracked scratch files.
- Out of scope: unit/default alignment with other clients (`gossipTimeout` stays seconds with default 5), IPv6 literals, S06 CA fallback, `init(stringLiteral:)`'s `fatalError`.

## Review Focus

1. Unencoded `@` in the password (`admin:p@ss@host`) — must parse with password `p@ss` (last `@` splits); today it traps. → Task 2 test `unencodedAtInPassword`.
2. Query values containing `=` (`connectionName=a=b`) — value is `a=b`. → Task 1 test `valueKeepsLaterEquals`.
3. Trailing `&` / bare `?` (`…?tls=false&`, `…:2113?`) — accepted, empty segments ignored. → Task 1 test `emptyQuerySegmentsIgnored`.
4. Upper-case scheme and boolean values (`ESDB://…?TLS=FALSE`) — accepted case-insensitively. → Task 1 `schemeIsCaseInsensitive`, Task 2 `booleanValuesAreCaseInsensitive`.
5. A path after the hosts (`esdb://host:2113/foo`) — error; a lone trailing `/` is fine. → Task 1 test `pathIsRejected`.

---

## File Structure

| File | Responsibility |
|---|---|
| Create `Sources/KurrentDB/Core/ClientSettings/Parser/ConnectionString.swift` | Structural split, percent-decoding, host validation. Produces scheme, credentials, endpoints, lower-cased parameters. |
| Modify `Sources/KurrentDB/Core/ClientSettings/URLScheme.swift` | `enum URLScheme` becomes `package` (it appears in `ConnectionString`'s package API). |
| Modify `Sources/KurrentDB/Core/ClientSettings/ClientSettings.swift` (`parse(connectionString:)`, lines ~242–332) | Map parameters to settings; value validation; unknown / duplicate keys. |
| Delete `Sources/KurrentDB/Core/ClientSettings/Parser/{ConnctionStringParser,URLSchemeParser,EndpointParser,UserCredentialsParser,QueryItemParser}.swift` | Replaced by `ConnectionString`. |
| Create `Tests/KurrentCoreTests/ConnectionStringTests.swift` | Structural tests for `ConnectionString` (Task 1). |
| Create `Tests/KurrentCoreTests/ConnectionStringValidationTests.swift` | Parameter validation, spec §1 regressions, no-trap sweep (Task 2). |
| Modify `Tests/KurrentCoreTests/ConnectionStringParserTests.swift` | Delete the old `ConnectionStringParser` suite (uses deleted classes); keep `ClientSettingsParsingTests` unchanged. |
| Modify `Sources/KurrentDB/KurrentDB.docc/Articles/Getting started.md` + `parse` doc comment | Encoding rule, strictness (Task 3). |

---

### Task 1: `ConnectionString` — structural parsing

**Files:**
- Create: `Sources/KurrentDB/Core/ClientSettings/Parser/ConnectionString.swift`
- Modify: `Sources/KurrentDB/Core/ClientSettings/URLScheme.swift` (`enum URLScheme` → `package enum URLScheme`)
- Test: `Tests/KurrentCoreTests/ConnectionStringTests.swift`

**Interfaces:**
- Produces:
  - `package struct ConnectionString: Sendable, Equatable`
  - `package init(parsing string: String) throws(KurrentError)`
  - `package let scheme: URLScheme`
  - `package let credentials: ConnectionString.Credentials?` with `package let username: String`, `package let password: String`
  - `package let endpoints: [Endpoint]` (non-empty)
  - `package let parameters: [String: String]` (keys lower-cased, values percent-decoded, no duplicates)

- [ ] **Step 1: Write the failing tests**

Create `Tests/KurrentCoreTests/ConnectionStringTests.swift`:

```swift
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
        #expect(reason { _ = try ConnectionString(parsing: input) } != nil)
    }

    // MARK: Hosts

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
        #expect(reason { _ = try ConnectionString(parsing: input) } != nil)
    }

    // MARK: Credentials

    @Test("Credentials split at the last '@' and the first ':' and are percent-decoded", arguments: [
        ("esdb://admin:changeit@localhost", "admin", "changeit"),
        ("esdb://admin:p@ss@localhost", "admin", "p@ss"),
        ("esdb://admin:p:ss@localhost", "admin", "p:ss"),
        ("esdb://admin:pa&tls=false&x=y@localhost", "admin", "pa&tls=false&x=y"),
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

    @Test("No '@' means no credentials, even when the query contains ':' and '@'")
    func atSignInQueryIsNotCredentials() throws {
        let parsed = try ConnectionString(parsing: "esdb://db.example.com:2113?connectionName=svc:a@b")
        #expect(parsed.credentials == nil)
        #expect(parsed.endpoints == [Endpoint(host: "db.example.com", port: 2113)])
        #expect(parsed.parameters == ["connectionname": "svc:a@b"])
    }

    @Test("Malformed credentials are rejected", arguments: [
        "esdb://admin@localhost",
        "esdb://:pw@localhost",
        "esdb://admin:p%zz@localhost",
        "esdb://admin:p%4@localhost",
        "esdb://admin:%FF@localhost",
    ])
    func badCredentials(input: String) {
        #expect(reason { _ = try ConnectionString(parsing: input) } != nil)
    }

    @Test("An unencoded '/', '?' or '#' in the password cannot be mistaken for structure", arguments: [
        "esdb://admin:pa?tls=false@db.example.com:2113",
        "esdb://admin:pa/x@db.example.com:2113",
        "esdb://admin:p#ss@db.example.com:2113",
    ])
    func unencodedDelimitersInPasswordFail(input: String) {
        #expect(reason { _ = try ConnectionString(parsing: input) } != nil)
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

    @Test("Empty query segments are ignored", arguments: ["esdb://localhost?", "esdb://localhost?&", "esdb://localhost?tls=false&", "esdb://localhost/?tls=false"])
    func emptyQuerySegmentsIgnored(input: String) throws {
        let parameters = try ConnectionString(parsing: input).parameters
        #expect(parameters.isEmpty || parameters == ["tls": "false"])
    }

    @Test("Duplicate keys are rejected regardless of case, and the error names the key, not the value")
    func duplicateKeys() {
        let message = reason { _ = try ConnectionString(parsing: "esdb://localhost?tls=true&TLS=s3cr3t") }
        #expect(message?.contains("tls") == true)
        #expect(message?.contains("s3cr3t") == false)
    }

    @Test("Malformed query items are rejected", arguments: [
        "esdb://localhost?tls",
        "esdb://localhost?=x",
        "esdb://localhost?tls=%zz",
        "esdb://localhost?t%zzls=true",
    ])
    func badQueryItems(input: String) {
        #expect(reason { _ = try ConnectionString(parsing: input) } != nil)
    }

    @Test("A path after the hosts is rejected; a lone '/' is fine")
    func pathIsRejected() throws {
        #expect(reason { _ = try ConnectionString(parsing: "esdb://localhost:2113/foo") } != nil)
        #expect(reason { _ = try ConnectionString(parsing: "esdb://localhost:2113/foo?tls=false") } != nil)
        #expect(try ConnectionString(parsing: "esdb://localhost:2113/").endpoints.count == 1)
    }

    @Test("A fragment is rejected")
    func fragmentIsRejected() {
        #expect(reason { _ = try ConnectionString(parsing: "esdb://localhost:2113?tls=false#x") } != nil)
    }

    @Test("Errors never echo the password")
    func errorsDoNotEchoPassword() {
        for input in ["esdb://admin:s3cr3t-pw@:2113", "esdb://admin:s3cr3t-pw%zz@localhost", "esdb://admin:s3cr3t-pw@localhost:99999", "esdb://admin:s3cr3t-pw@localhost/path"] {
            let message = reason { _ = try ConnectionString(parsing: input) }
            #expect(message != nil)
            #expect(message?.contains("s3cr3t") == false)
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift build --build-tests 2>&1 | grep -E "error:" | head -3`
Expected: compile error `cannot find 'ConnectionString' in scope`.

- [ ] **Step 3: Make `URLScheme` package-visible**

In `Sources/KurrentDB/Core/ClientSettings/URLScheme.swift` change `enum URLScheme: String {` to `package enum URLScheme: String {`.

- [ ] **Step 4: Implement `ConnectionString`**

Create `Sources/KurrentDB/Core/ClientSettings/Parser/ConnectionString.swift`:

```swift
//
//  ConnectionString.swift
//  KurrentCore
//

/// A KurrentDB connection string split into its RFC 3986 components.
///
/// The input is cut in a fixed order — scheme, authority (up to the first `/`, `?` or `#`),
/// userinfo (left of the authority's last `@`), hosts, query — and each component is parsed only
/// from its own slice, so characters in a password can never change hosts or parameters.
/// Userinfo and query items are percent-decoded. Meaning and validation of the parameters belong
/// to `ClientSettings.parse(connectionString:)`.
///
/// Error reasons name the component that is wrong and never echo input text: a connection string
/// may carry credentials.
package struct ConnectionString: Sendable, Equatable {
    package struct Credentials: Sendable, Equatable {
        package let username: String
        package let password: String
    }

    package let scheme: URLScheme
    package let credentials: Credentials?
    package let endpoints: [Endpoint]
    /// Query parameters. Keys are lower-cased, values percent-decoded; a key appears at most once.
    package let parameters: [String: String]

    package init(parsing string: String) throws(KurrentError) {
        guard let schemeEnd = string.range(of: "://"),
              let scheme = URLScheme(rawValue: string[..<schemeEnd.lowerBound].lowercased())
        else {
            throw Self.failure("Unknown or missing URL scheme; expected esdb://, kurrentdb://, kurrent:// or kdb:// (optionally with +discover).")
        }
        let rest = string[schemeEnd.upperBound...]

        guard !rest.contains("#") else {
            throw Self.failure("Connection strings take no fragment; percent-encode '#' as %23 in credentials or values.")
        }

        let authorityEnd = rest.firstIndex { $0 == "/" || $0 == "?" } ?? rest.endIndex
        let authority = rest[..<authorityEnd]
        var tail = rest[authorityEnd...]
        if tail.first == "/" {
            tail = tail.dropFirst()
        }
        let query: Substring
        if tail.isEmpty {
            query = ""
        } else if tail.first == "?" {
            query = tail.dropFirst()
        } else {
            throw Self.failure("Connection strings take no path; only '/' may follow the hosts. Percent-encode '/' as %2F in credentials.")
        }

        let hostList: Substring
        if let at = authority.lastIndex(of: "@") {
            credentials = try Self.parseCredentials(authority[..<at])
            hostList = authority[authority.index(after: at)...]
        } else {
            credentials = nil
            hostList = authority
        }

        self.scheme = scheme
        endpoints = try Self.parseEndpoints(hostList)
        parameters = try Self.parseParameters(query)
    }

    // MARK: - Components

    private static func parseCredentials(_ userinfo: Substring) throws(KurrentError) -> Credentials {
        guard let colon = userinfo.firstIndex(of: ":") else {
            throw failure("Credentials must be 'username:password'; percent-encode ':' in the username as %3A.")
        }
        let username = try percentDecoded(userinfo[..<colon], field: "username")
        let password = try percentDecoded(userinfo[userinfo.index(after: colon)...], field: "password")
        guard !username.isEmpty else {
            throw failure("The username in the credentials is empty.")
        }
        return Credentials(username: username, password: password)
    }

    private static func parseEndpoints(_ hostList: Substring) throws(KurrentError) -> [Endpoint] {
        guard !hostList.isEmpty else {
            throw failure("Connection string doesn't have a host.")
        }
        var endpoints: [Endpoint] = []
        for entry in hostList.split(separator: ",", omittingEmptySubsequences: false) {
            let host: Substring
            var port: UInt32?
            if let colon = entry.firstIndex(of: ":") {
                host = entry[..<colon]
                let portText = entry[entry.index(after: colon)...]
                guard !portText.isEmpty,
                      portText.utf8.allSatisfy(isDigit),
                      let value = UInt32(portText),
                      (1 ... 65535).contains(value)
                else {
                    throw failure("Every host port must be a number from 1 to 65535.")
                }
                port = value
            } else {
                host = entry
            }
            guard isValidHost(host) else {
                throw failure("Every host must be a host name or an IPv4 address.")
            }
            endpoints.append(Endpoint(host: String(host), port: port))
        }
        return endpoints
    }

    private static func parseParameters(_ query: Substring) throws(KurrentError) -> [String: String] {
        var parameters: [String: String] = [:]
        for item in query.split(separator: "&", omittingEmptySubsequences: true) {
            guard let equals = item.firstIndex(of: "=") else {
                throw failure("Every connection string parameter must be 'name=value'.")
            }
            let key = try percentDecoded(item[..<equals], field: "parameter name").lowercased()
            guard !key.isEmpty else {
                throw failure("A connection string parameter has an empty name.")
            }
            let value = try percentDecoded(item[item.index(after: equals)...], field: "value of '\(key)'")
            guard parameters.updateValue(value, forKey: key) == nil else {
                throw failure("Duplicate connection string parameter '\(key)'.")
            }
        }
        return parameters
    }

    // MARK: - Helpers

    /// Host names (ASCII letters, digits, '-', '_', '.') or dotted-quad IPv4. A name whose labels
    /// are all numeric must be a valid IPv4 address, so "192.168" is rejected.
    private static func isValidHost(_ host: Substring) -> Bool {
        guard !host.isEmpty else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.allSatisfy({ !$0.isEmpty }) else { return false }
        let allowedBytes = host.utf8.allSatisfy { byte in
            isDigit(byte)
                || (UInt8(ascii: "a") ... UInt8(ascii: "z")).contains(byte)
                || (UInt8(ascii: "A") ... UInt8(ascii: "Z")).contains(byte)
                || byte == UInt8(ascii: "-") || byte == UInt8(ascii: "_") || byte == UInt8(ascii: ".")
        }
        guard allowedBytes else { return false }
        if labels.allSatisfy({ $0.utf8.allSatisfy(isDigit) }) {
            return labels.count == 4 && labels.allSatisfy { UInt8($0) != nil }
        }
        return true
    }

    private static func percentDecoded(_ text: Substring, field: String) throws(KurrentError) -> String {
        guard text.contains("%") else { return String(text) }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(text.utf8.count)
        var iterator = text.utf8.makeIterator()
        while let byte = iterator.next() {
            guard byte == UInt8(ascii: "%") else {
                bytes.append(byte)
                continue
            }
            guard let high = iterator.next().flatMap(hexValue), let low = iterator.next().flatMap(hexValue) else {
                throw failure("Invalid percent-encoding in the \(field).")
            }
            bytes.append(high << 4 | low)
        }
        guard let decoded = String(validating: bytes, as: UTF8.self) else {
            throw failure("The \(field) is not valid UTF-8 after percent-decoding.")
        }
        return decoded
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(byte)
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0") ... UInt8(ascii: "9"): byte - UInt8(ascii: "0")
        case UInt8(ascii: "A") ... UInt8(ascii: "F"): byte - UInt8(ascii: "A") + 10
        case UInt8(ascii: "a") ... UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
        default: nil
        }
    }

    private static func failure(_ reason: String) -> KurrentError {
        .internalParsingError(reason: reason)
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift build --build-tests 2>&1 | grep -E "error:|Build complete" | head -3 && swift test --skip-build --no-parallel --disable-xctest --enable-swift-testing --filter ConnectionStringTests 2>&1 | grep -E "✘|Test run with"`
Expected: `Test run with … passed`, no `✘`.

- [ ] **Step 6: Commit**

```bash
git add Sources/KurrentDB/Core/ClientSettings/Parser/ConnectionString.swift Sources/KurrentDB/Core/ClientSettings/URLScheme.swift Tests/KurrentCoreTests/ConnectionStringTests.swift
git commit -m "[ADD] split connection strings into RFC 3986 components with percent-decoding"
```

---

### Task 2: `ClientSettings.parse` on top of `ConnectionString`; delete the regex parsers

**Files:**
- Modify: `Sources/KurrentDB/Core/ClientSettings/ClientSettings.swift` (body of `public static func parse(connectionString:)`)
- Delete: `Sources/KurrentDB/Core/ClientSettings/Parser/ConnctionStringParser.swift`, `URLSchemeParser.swift`, `EndpointParser.swift`, `UserCredentialsParser.swift`, `QueryItemParser.swift`
- Modify: `Tests/KurrentCoreTests/ConnectionStringParserTests.swift` (delete the `@Suite("ConnectionStringParser") struct ConnectionStringParser { … }` block, lines 11–64; keep `ClientSettingsParsingTests`)
- Test: `Tests/KurrentCoreTests/ConnectionStringValidationTests.swift`

**Interfaces:**
- Consumes: `ConnectionString(parsing:)`, `.scheme`, `.credentials`, `.endpoints`, `.parameters` from Task 1.
- Produces: no new API; `parse(connectionString:)` keeps its signature.

- [ ] **Step 1: Write the failing tests**

Create `Tests/KurrentCoreTests/ConnectionStringValidationTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift build --build-tests 2>&1 | grep -E "error:|Build complete" | head -3 && swift test --skip-build --no-parallel --disable-xctest --enable-swift-testing --filter "ConnectionStringValidationTests" 2>&1 | grep -E "✘ Test|signal|Fatal error|Test run with" | head -12`
Expected: failures and/or a crash (`unencodedAtInPassword` traps with the old parser; `ampersandInPasswordDoesNotDisableTLS`, `duplicateParameters`, `keepAliveOverflow`, `malformedValues`, `unknownParameter`, `halfX509` fail). If the process crashes before reporting, that is the expected S03/S01 trap.

- [ ] **Step 3: Rewrite `parse(connectionString:)`**

Replace the body of `public static func parse(connectionString: String) throws(KurrentError) -> Self` in `Sources/KurrentDB/Core/ClientSettings/ClientSettings.swift` (from `let schemeParser = URLSchemeParser()` through the closing `)` of `return Self(...)`) with the code below, and add the `ConnectionStringParameters` helper at the end of the file. Keep the method's doc comment; Task 3 updates it.

```swift
    public static func parse(connectionString: String) throws(KurrentError) -> Self {
        let parsed = try ConnectionString(parsing: connectionString)
        let parameters = try ConnectionStringParameters(parsed.parameters)

        let clusterMode: TopologyClusterMode = if parsed.scheme == .dnsDiscover {
            .dns(domain: parsed.endpoints[0])
        } else if parsed.endpoints.count > 1 {
            .seeds(parsed.endpoints)
        } else {
            .standalone(endpoint: parsed.endpoints[0])
        }

        let nodePreference: NodePreference
        if let raw = try parameters.string("nodepreference") {
            guard let preference = NodePreference(rawValue: raw.lowercased()) else {
                throw .internalParsingError(reason: "Parameter 'nodepreference' must be leader, follower, random or readOnlyReplica.")
            }
            nodePreference = preference
        } else {
            nodePreference = .leader
        }

        let gossipTimeout = try parameters.duration("gossiptimeout", unit: .seconds) ?? .seconds(5)
        let maxDiscoveryAttempts = try parameters.positiveInteger("maxdiscoverattempts", as: UInt16.self) ?? 10
        let discoveryInterval = try parameters.duration("discoveryinterval", unit: .milliseconds) ?? .milliseconds(100)

        let certFile = try parameters.string("usercertfile")
        let keyFile = try parameters.string("userkeyfile")
        let authentication: Authentication?
        switch (certFile, keyFile) {
        case let (certFile?, keyFile?):
            authentication = .x509(certFile: certFile, keyFile: keyFile)
        case (nil, nil):
            authentication = parsed.credentials.map { .credentials(username: $0.username, password: $0.password) }
        default:
            throw .internalParsingError(reason: "Parameters 'usercertfile' and 'userkeyfile' must be given together.")
        }

        // Connection string values are in seconds. Only both together replace the default.
        let keepAliveInterval = try parameters.duration("keepaliveinterval", unit: .seconds)
        let keepAliveTimeout = try parameters.duration("keepalivetimeout", unit: .seconds)
        let keepAlive: KeepAlive = if let keepAliveInterval, let keepAliveTimeout {
            .init(interval: keepAliveInterval, timeout: keepAliveTimeout)
        } else {
            .default
        }

        let connectionName = try parameters.string("connectionname")
        let secure = try parameters.bool("tls") ?? true

        // The client certificate is presented in the TLS handshake, so X.509 needs TLS.
        if case .x509 = authentication, !secure {
            throw .internalParsingError(reason: "X.509 authentication (userCertFile/userKeyFile) requires a TLS connection; remove tls=false.")
        }

        let tlsVerifyCert = try parameters.bool("tlsverifycert") ?? true

        var certificates: [TLSConfig.CertificateSource] = []
        if let tlsCaFilePath = try parameters.string("tlscafile"),
           let certificate = parseCertificate(path: tlsCaFilePath) {
            certificates.append(certificate)
        }

        // Validated as a duration so a deadline computed from it cannot overflow; stored in ms.
        let defaultDeadline: Int = if let deadline = try parameters.duration("defaultdeadline", unit: .milliseconds) {
            Int(deadline.components.seconds) * 1000 + Int(deadline.components.attoseconds / 1_000_000_000_000_000)
        } else {
            .max
        }

        return Self(
            clusterMode: clusterMode,
            certificates: certificates,
            nodePreference: nodePreference,
            gossipTimeout: gossipTimeout,
            secure: secure,
            tlsVerifyCert: tlsVerifyCert,
            defaultDeadline: defaultDeadline,
            connectionName: connectionName,
            keepAlive: keepAlive,
            authentication: authentication,
            discoveryInterval: discoveryInterval,
            maxDiscoveryAttempts: maxDiscoveryAttempts
        )
    }
```

Add at the end of `ClientSettings.swift`:

```swift
/// Typed, validated access to a connection string's query parameters.
///
/// Every getter returns nil for an absent parameter and throws for a present but malformed one,
/// naming the parameter, never its value.
private struct ConnectionStringParameters {
    enum DurationUnit {
        case seconds, milliseconds

        var nanoseconds: Int64 {
            switch self {
            case .seconds: 1_000_000_000
            case .milliseconds: 1_000_000
            }
        }
    }

    static let known: Set<String> = [
        "tls", "tlsverifycert", "tlscafile", "connectionname", "nodepreference",
        "gossiptimeout", "maxdiscoverattempts", "discoveryinterval", "defaultdeadline",
        "keepaliveinterval", "keepalivetimeout", "usercertfile", "userkeyfile",
    ]

    private let values: [String: String]

    init(_ values: [String: String]) throws(KurrentError) {
        if let unknown = values.keys.sorted().first(where: { !Self.known.contains($0) }) {
            throw .internalParsingError(reason: "Unknown connection string parameter '\(unknown)'.")
        }
        self.values = values
    }

    func string(_ key: String) throws(KurrentError) -> String? {
        guard let value = values[key] else { return nil }
        guard !value.isEmpty else {
            throw .internalParsingError(reason: "Parameter '\(key)' must not be empty.")
        }
        return value
    }

    func bool(_ key: String) throws(KurrentError) -> Bool? {
        guard let value = values[key] else { return nil }
        switch value.lowercased() {
        case "true": return true
        case "false": return false
        default: throw .internalParsingError(reason: "Parameter '\(key)' must be true or false.")
        }
    }

    func positiveInteger<T: FixedWidthInteger>(_ key: String, as _: T.Type) throws(KurrentError) -> T? {
        guard let value = values[key] else { return nil }
        guard let number = T(value), number > 0 else {
            throw .internalParsingError(reason: "Parameter '\(key)' must be a positive integer no larger than \(T.max).")
        }
        return number
    }

    /// A positive duration whose nanosecond value fits in `Int64`, so nothing downstream
    /// (NIO `TimeAmount`, deadline arithmetic) can overflow.
    func duration(_ key: String, unit: DurationUnit) throws(KurrentError) -> Duration? {
        guard let value = values[key] else { return nil }
        guard let number = Int64(value), number > 0,
              !number.multipliedReportingOverflow(by: unit.nanoseconds).overflow
        else {
            throw .internalParsingError(reason: "Parameter '\(key)' must be a positive integer within range.")
        }
        return switch unit {
        case .seconds: .seconds(number)
        case .milliseconds: .milliseconds(number)
        }
    }
}
```

Note on `defaultDeadline`: the setting stays an `Int` of milliseconds (public `ClientSettings.defaultDeadline: Int`). Converting back from the validated `Duration` keeps one source of range checking; for `.milliseconds(n)` the formula yields exactly `n`.

- [ ] **Step 4: Delete the old parsers and their suite**

```bash
git rm Sources/KurrentDB/Core/ClientSettings/Parser/ConnctionStringParser.swift Sources/KurrentDB/Core/ClientSettings/Parser/URLSchemeParser.swift Sources/KurrentDB/Core/ClientSettings/Parser/EndpointParser.swift Sources/KurrentDB/Core/ClientSettings/Parser/UserCredentialsParser.swift Sources/KurrentDB/Core/ClientSettings/Parser/QueryItemParser.swift
```

In `Tests/KurrentCoreTests/ConnectionStringParserTests.swift` delete the whole `@Suite("ConnectionStringParser") struct ConnectionStringParser { … }` block (it calls the deleted classes; Task 1's `ConnectionStringTests` covers the same scheme and host cases). Keep `// MARK: - ClientSettings.parse() integration tests` and `ClientSettingsParsingTests` untouched.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift build --build-tests 2>&1 | grep -E "error:|Build complete" | head -3 && swift test --skip-build --no-parallel --disable-xctest --enable-swift-testing --filter "ConnectionStringValidationTests|ConnectionStringTests|ClientSettingsParsingTests|UntrustedInputTests|AuthenticationTests" 2>&1 | grep -E "✘|Test run with"`
Expected: all pass. `ClientSettingsParsingTests` must pass unchanged — it is the compatibility check for valid strings.

- [ ] **Step 6: Run the offline suites under Swift 6.0 (Linux)**

Run (from a clean worktree so a local `Package.resolved` does not pin newer dependencies):
```bash
W=$(mktemp -d)/wt; git worktree add -q "$W" HEAD
docker run --rm --platform linux/arm64 -v "$W":/w -w /w swift:6.0-jammy swift test --no-parallel --disable-xctest --enable-swift-testing --filter "ConnectionStringValidationTests|ConnectionStringTests|ClientSettingsParsingTests|UntrustedInputTests"
git worktree remove --force "$W"
```
Expected: all pass (this checks `String(validating:as:)` and the sweep on Linux).

- [ ] **Step 7: Commit**

```bash
git add Sources/KurrentDB/Core/ClientSettings/ClientSettings.swift Tests/KurrentCoreTests/ConnectionStringValidationTests.swift Tests/KurrentCoreTests/ConnectionStringParserTests.swift
git commit -m "[FIX] parse connection strings by component and reject unknown, duplicate and out-of-range parameters"
```
(`git rm` in Step 4 already staged the deletions.)

---

### Task 3: Documentation

**Files:**
- Modify: `Sources/KurrentDB/KurrentDB.docc/Articles/Getting started.md` (after the parameter table, before "When connecting to an insecure instance…")
- Modify: `Sources/KurrentDB/Core/ClientSettings/ClientSettings.swift` (doc comment of `parse(connectionString:)`, the `- Throws:` line)

- [ ] **Step 1: Add the encoding and strictness rules to Getting started**

Insert after the parameter table in `Getting started.md`:

````markdown
Parameter names and the scheme are case-insensitive. A parameter the client does not know, a parameter given twice, or a value it cannot use (for example `tls=yes` or `gossipTimeout=0`) makes `ClientSettings.parse(connectionString:)` throw; the error names the parameter, never its value.

The username, the password and parameter values are percent-decoded. Encode `/`, `?`, `#` and `%` in a password — other characters, including `@`, `:` and `&`, may be written as they are. The simplest way is to encode the whole password:

```swift
let password = "p@ss/w%rd#1"
let encoded = password.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed)!
let parsed = try ClientSettings.parse(connectionString: "kurrentdb://admin:\(encoded)@localhost:2113")
```
````

- [ ] **Step 2: Update the `- Throws:` line of `parse(connectionString:)`**

Replace
`/// - Throws: `KurrentError.internalParsingError` if the string is malformed or missing required components.`
with
`/// - Throws: `KurrentError.internalParsingError` if the string is malformed, lacks a host, or has an unknown, duplicate or invalid parameter. The reason names the component or parameter, never its value.`

- [ ] **Step 3: Compile the documentation examples**

Run: `scripts/check-doc-snippets.sh > /tmp/snippets.log 2>&1; echo "exit=$?"`
Expected: `exit=0`.

- [ ] **Step 4: Full suite against the local cluster**

Run: `docker compose -f server/docker-compose.yaml up -d` (if not running), then `swift test --no-parallel --disable-xctest --enable-swift-testing 2>&1 | grep -E "✘|Test run with"`
Expected: no `✘`.

- [ ] **Step 5: Commit**

```bash
git add "Sources/KurrentDB/KurrentDB.docc/Articles/Getting started.md" Sources/KurrentDB/Core/ClientSettings/ClientSettings.swift
git commit -m "[UPDATE] document connection-string encoding and strict parameter validation"
```

---

## Self-Review

- Spec §3 steps 1–6 → Task 1 (`ConnectionString`), each with tests; host-validity ruling and `/`-only path from the spec revision are in `isValidHost` / `pathIsRejected`.
- Spec §4 table → Task 2 `ConnectionStringParameters` + `malformedValues`, `duplicateParameters`, `unknownParameter`, `halfX509`, `durationOverflow`.
- Spec §5 structure → Task 1 creates the type, Task 2 deletes the classes; public API untouched.
- Spec §6 tests → §1 table rows in Task 2 (S01 section) and Task 1 (`credentials`, `unencodedDelimitersInPasswordFail`, `atSignInQueryIsNotCredentials`); percent-decoding rows in Task 1; sweep `noInputTraps`; legacy valid cases kept via `ClientSettingsParsingTests` unchanged and host cases moved into `ConnectionStringTests.hosts`.
- Spec §7 decisions → unknown key error (Task 2), RFC decoding (Task 1); §8 release note goes into the PR description.
- Types: `ConnectionString.Credentials(username:password:)`, `parameters: [String: String]`, `URLScheme` (package) consistent across tasks.
