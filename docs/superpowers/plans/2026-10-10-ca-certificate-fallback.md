# CA Certificate Fallback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A CA certificate that cannot be read must never silently widen trust to the system roots: connection strings and `fromEnv` throw, a new builder `certificate(path:fallback:)` throws unless the caller explicitly chooses `.systemTrustRoots`, and the deprecated `certificate(path:)` makes the client refuse to connect.

**Architecture:** A non-logging `package` helper `readableCertificate(path:)` decides readability (missing, unreadable or empty file → nil). `parse` and the new builder use it and report failure immediately. The deprecated builder cannot throw, so it records `hasUnreadableCertificate` in the settings; `trustRoots` then never returns `.systemDefault`, and `ConnectionProvider.makeClient` throws `initializationError` before any transport is built.

**Tech Stack:** Swift 6.0+, Swift Testing, grpc-swift-nio-transport TLS config. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-10-09-ca-certificate-fallback-design.md`

## Global Constraints

- Default behaviour is to report the failure. Connection strings and `fromEnv` offer no relaxation.
- Public API: add `public enum CertificateFallback: Sendable, Equatable { case none; case systemTrustRoots }` and `public func certificate(path: String, fallback: CertificateFallback) throws(KurrentError) -> Self` (no default for `fallback`). Deprecate `certificate(path:)` with message `"Use certificate(path:fallback:), which reports an unreadable file instead of widening trust."`. `parseCertificate(path:)`, `certificate(source:)`, `certificates`, `crtInBundle` unchanged.
- "Unreadable" = file missing, not readable, or empty. A readable file with a malformed certificate keeps today's behaviour (NIO fails when building TLS).
- Error reasons never contain the path (exact texts in the tasks).
- `KurrentError.initializationError` is not a node failure, so `withRetry` must not retry it.
- English `//` / `///` comments. Commit subjects `[TAG] message`; **no `Co-Authored-By:` or any other trailer**. Stage explicit paths only.
- **Every commit must build and pass its tests** (the owner merges with rebase-and-merge). Never commit with failing tests.

## Review Focus

1. The connection string's `tlsCaFile` pointing at a directory instead of a file — must throw like a missing file. → Task 1 test `parseRejectsDirectory`.
2. `.systemTrustRoots` when a readable CA was already added via `certificate(source:)` — the existing CA must stay and `trustRoots` must be `.certificates`, not `.systemDefault`. → Task 1 test `systemTrustRootsKeepsExistingCertificates`.
3. Deprecated `certificate(path:)` with an unreadable file on an **insecure** (`tls=false`) client — still refuses to connect (a CA configuration error is reported regardless of TLS). → Task 2 test `refusesToConnectEvenWhenInsecure`.
4. Deprecated `certificate(path:)` with an unreadable file followed by a readable `certificate(source:)` — `trustRoots` must be the readable CA only and the client must still refuse to connect. → Task 2 test `unreadableStaysRecordedAfterAnotherCertificate`.
5. Tests that rely on file permissions under root (Docker CI) — `chmod 000` is still readable by root, so that case is skipped when `getuid() == 0`. → Task 1 test `parseRejectsUnreadableFile`.

---

## File Structure

| File | Responsibility |
|---|---|
| Create `Sources/KurrentDB/Core/ClientSettings/CertificateFallback.swift` | The public `CertificateFallback` enum. |
| Modify `Sources/KurrentDB/Core/ClientSettings/ClientSettings.swift` | `readableCertificate(path:)`, `tlsCaFile` handling in `parse`, the new builder, the deprecated builder, `hasUnreadableCertificate`, `trustRoots`. |
| Modify `Sources/KurrentDB/Core/ConnectionProvider.swift` (`makeClient(for:)`, ~line 370) | Refuse to build a transport when `hasUnreadableCertificate`. |
| Create `Tests/KurrentCoreTests/CertificateFallbackTests.swift` | Task 1 tests. |
| Create `Tests/MockClientTests/LegacyCertificatePathTests.swift` | Task 2 tests. |
| Modify `README.md`, `Sources/KurrentDB/KurrentDB.docc/Articles/Getting started.md` | Task 3 docs. |

---

### Task 1: `CertificateFallback`, the new builder, and strict `tlsCaFile`

**Files:**
- Create: `Sources/KurrentDB/Core/ClientSettings/CertificateFallback.swift`
- Modify: `Sources/KurrentDB/Core/ClientSettings/ClientSettings.swift`
- Test: `Tests/KurrentCoreTests/CertificateFallbackTests.swift`

**Interfaces:**
- Produces: `public enum CertificateFallback { case none, systemTrustRoots }`; `public func certificate(path: String, fallback: CertificateFallback) throws(KurrentError) -> Self`; `package static func readableCertificate(path: String) -> TLSConfig.CertificateSource?` (Task 2 reuses it).

- [ ] **Step 1: Write the failing tests**

Create `Tests/KurrentCoreTests/CertificateFallbackTests.swift`:

```swift
//
//  CertificateFallbackTests.swift
//  KurrentCoreTests
//
//  A CA the caller named but the client cannot read must never widen trust to the system roots
//  without the caller asking for it (security review S06).
//

import Foundation
@testable import KurrentDB
import Testing

@Suite("CA certificate fallback")
struct CertificateFallbackTests {
    private static let pem = "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----\n"

    private func temporaryFile(_ contents: String) throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ca-\(UUID().uuidString).crt")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    private var missingPath: String {
        FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).crt").path
    }

    /// The reason of a thrown parsing or initialization error, or nil when nothing was thrown.
    private func reason(_ body: () throws(KurrentError) -> Void) -> String? {
        do throws(KurrentError) {
            try body()
            return nil
        } catch {
            switch error {
            case let .internalParsingError(reason), let .initializationError(reason):
                return reason
            default:
                return "\(error)"
            }
        }
    }

    private func isSystemDefault(_ settings: ClientSettings) -> Bool {
        if case .systemDefault = settings.trustRoots { return true }
        return false
    }

    private func trustedCertificateCount(_ settings: ClientSettings) -> Int? {
        if case let .certificates(certificates) = settings.trustRoots { return certificates.count }
        return nil
    }

    // MARK: Connection string

    @Test("tlsCaFile naming a missing file throws without echoing the path")
    func parseRejectsMissingFile() {
        let path = missingPath
        let message = reason { () throws(KurrentError) in _ = try ClientSettings.parse(connectionString: "esdb://localhost:2113?tlsCaFile=\(path)") }
        #expect(message?.contains("tlsCaFile") == true)
        #expect(message?.contains(path) == false)
    }

    @Test("tlsCaFile naming an empty file throws")
    func parseRejectsEmptyFile() throws {
        let path = try temporaryFile("")
        #expect(reason { () throws(KurrentError) in _ = try ClientSettings.parse(connectionString: "esdb://localhost:2113?tlsCaFile=\(path)") } != nil)
    }

    @Test("tlsCaFile naming a directory throws")
    func parseRejectsDirectory() {
        let path = FileManager.default.temporaryDirectory.path
        #expect(reason { () throws(KurrentError) in _ = try ClientSettings.parse(connectionString: "esdb://localhost:2113?tlsCaFile=\(path)") } != nil)
    }

    @Test("tlsCaFile naming a file without read permission throws", .enabled(if: getuid() != 0))
    func parseRejectsUnreadableFile() throws {
        let path = try temporaryFile(Self.pem)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path) }
        #expect(reason { () throws(KurrentError) in _ = try ClientSettings.parse(connectionString: "esdb://localhost:2113?tlsCaFile=\(path)") } != nil)
    }

    @Test("tlsCaFile naming a readable file trusts exactly that CA")
    func parseAcceptsReadableFile() throws {
        let path = try temporaryFile(Self.pem)
        let settings = try ClientSettings.parse(connectionString: "esdb://localhost:2113?tlsCaFile=\(path)")
        #expect(trustedCertificateCount(settings) == 1)
    }

    // MARK: certificate(path:fallback:)

    @Test("fallback: .none throws for an unreadable file without echoing the path")
    func noneThrows() {
        let path = missingPath
        let message = reason { () throws(KurrentError) in _ = try ClientSettings.localhost().secure(true).certificate(path: path, fallback: .none) }
        #expect(message != nil)
        #expect(message?.contains(path) == false)
    }

    @Test("fallback: .none adds a readable file")
    func noneAddsReadableFile() throws {
        let settings = try ClientSettings.localhost().secure(true).certificate(path: try temporaryFile(Self.pem), fallback: .none)
        #expect(trustedCertificateCount(settings) == 1)
    }

    @Test("fallback: .systemTrustRoots falls back to the system roots when nothing else is configured")
    func systemTrustRootsFallsBack() throws {
        let settings = try ClientSettings.localhost().secure(true).certificate(path: missingPath, fallback: .systemTrustRoots)
        #expect(settings.certificates.isEmpty)
        #expect(isSystemDefault(settings))
    }

    @Test("fallback: .systemTrustRoots keeps a CA that is already configured")
    func systemTrustRootsKeepsExistingCertificates() throws {
        let readable = try temporaryFile(Self.pem)
        let settings = try ClientSettings.localhost().secure(true)
            .certificate(source: .file(path: readable, format: .pem))
            .certificate(path: missingPath, fallback: .systemTrustRoots)
        #expect(trustedCertificateCount(settings) == 1)
        #expect(!isSystemDefault(settings))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift build --build-tests 2>&1 | grep -E "error:" | head -3`
Expected: compile error — `CertificateFallback` / `certificate(path:fallback:)` not found.

- [ ] **Step 3: Add `CertificateFallback`**

Create `Sources/KurrentDB/Core/ClientSettings/CertificateFallback.swift`:

```swift
//
//  CertificateFallback.swift
//  KurrentDB
//

/// What ``ClientSettings/certificate(path:fallback:)`` does when the CA file it was given cannot
/// be read (missing, not readable, or empty).
///
/// There is deliberately no default: falling back widens trust from one private CA to every
/// certificate authority the system trusts, so it has to be written out.
public enum CertificateFallback: Sendable, Equatable {
    /// No fallback: throw `KurrentError.initializationError`.
    case none
    /// Leave the configured CA out and trust the system's root certificates instead. Use it only
    /// when one configuration is shared by environments where the CA file is legitimately absent.
    case systemTrustRoots
}
```

- [ ] **Step 4: Add the readability helper, the new builder, and strict `tlsCaFile`**

In `Sources/KurrentDB/Core/ClientSettings/ClientSettings.swift`:

(a) Directly after `public static func parseCertificate(path: String) -> TLSConfig.CertificateSource? { … }` add:

```swift
    /// A certificate source for a CA file the client can actually read, or nil when the file is
    /// missing, not readable, a directory, or empty. Logs nothing: each caller reports the failure
    /// in its own way, without the path.
    package static func readableCertificate(path: String) -> TLSConfig.CertificateSource? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), !data.isEmpty else {
            return nil
        }
        let isPEM = String(data: data.prefix(27), encoding: .ascii) == "-----BEGIN CERTIFICATE-----"
        return .file(path: path, format: isPEM ? .pem : .der)
    }
```

(b) In `parse(connectionString:policy:)` replace

```swift
        var certificates: [TLSConfig.CertificateSource] = []
        if let tlsCaFilePath = try parameters.string("tlscafile"),
           let certificate = parseCertificate(path: tlsCaFilePath) {
            certificates.append(certificate)
        }
```

with

```swift
        var certificates: [TLSConfig.CertificateSource] = []
        if let tlsCaFilePath = try parameters.string("tlscafile") {
            // A CA the caller named but the client cannot read must not quietly become "trust the
            // system roots".
            guard let certificate = readableCertificate(path: tlsCaFilePath) else {
                throw .internalParsingError(reason: "Parameter 'tlsCaFile' names a CA file that cannot be read.")
            }
            certificates.append(certificate)
        }
```

(c) In `extension ClientSettings: Buildable`, directly after `public func certificate(source:)`, add:

```swift
    /// Returns a copy with a CA certificate loaded from a file appended.
    ///
    /// - Parameters:
    ///   - path: File-system path to the certificate (PEM or DER).
    ///   - fallback: What to do when the file is missing, not readable or empty. `.none` throws;
    ///     `.systemTrustRoots` leaves it out, so the system's root certificates are trusted if no
    ///     other CA is configured. There is no default on purpose.
    /// - Throws: `KurrentError.initializationError` when the file cannot be read and `fallback` is `.none`.
    @discardableResult
    public func certificate(path: String, fallback: CertificateFallback) throws(KurrentError) -> Self {
        if let certificate = Self.readableCertificate(path: path) {
            return withCopy { $0.certificates.append(certificate) }
        }
        switch fallback {
        case .none:
            throw .initializationError(reason: "The CA certificate file passed to certificate(path:fallback:) cannot be read.")
        case .systemTrustRoots:
            logger.warning("Configured CA certificate file is unreadable; using the system trust roots as requested (fallback: .systemTrustRoots).")
            return self
        }
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift build --build-tests 2>&1 | grep -E "error:|Build complete" | head -3 && swift test --skip-build --no-parallel --disable-xctest --enable-swift-testing --filter "CertificateFallbackTests|ClientSettingsParsingTests|ConnectionStringValidationTests|ConnectionStringTests" 2>&1 | grep -E "✘|Test run with"`
Expected: all pass (the unreadable-permission test is skipped only as root).

- [ ] **Step 6: Commit**

```bash
git add Sources/KurrentDB/Core/ClientSettings/CertificateFallback.swift Sources/KurrentDB/Core/ClientSettings/ClientSettings.swift Tests/KurrentCoreTests/CertificateFallbackTests.swift
git commit -m "[ADD] certificate(path:fallback:) and reject an unreadable tlsCaFile instead of trusting the system roots"
```

---

### Task 2: The deprecated `certificate(path:)` refuses to connect

**Files:**
- Modify: `Sources/KurrentDB/Core/ClientSettings/ClientSettings.swift` (stored property, `trustRoots`, `certificate(path:)`)
- Modify: `Sources/KurrentDB/Core/ConnectionProvider.swift` (`makeClient(for:)`)
- Test: `Tests/MockClientTests/LegacyCertificatePathTests.swift`

**Interfaces:**
- Consumes: `ClientSettings.readableCertificate(path:)` from Task 1.
- Produces: `package var hasUnreadableCertificate: Bool` on `ClientSettings`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/MockClientTests/LegacyCertificatePathTests.swift`:

```swift
//
//  LegacyCertificatePathTests.swift
//  swift-kurrentdb
//
//  The deprecated certificate(path:) cannot throw. When its file is unreadable it must not widen
//  trust to the system roots: trustRoots never falls back and the client refuses to connect.
//  No server needed — the refusal happens before any transport is built.
//

import Foundation
@testable import KurrentDB
import Testing

@Suite("Deprecated certificate(path:)")
struct LegacyCertificatePathTests {
    private static let endpoint = Endpoint(host: "127.0.0.1", port: 1)
    private static let pem = "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----\n"

    private var missingPath: String {
        FileManager.default.temporaryDirectory.appendingPathComponent("missing-\(UUID().uuidString).crt").path
    }

    private func temporaryFile(_ contents: String) throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ca-\(UUID().uuidString).crt")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    private func isInitializationError(_ error: any Error) -> Bool {
        if case .initializationError = error as? KurrentError { return true }
        return false
    }

    @Test("An unreadable file makes the client refuse to connect")
    func refusesToConnect() {
        let settings = ClientSettings.localhost().secure(true).certificate(path: missingPath)
        let provider = ConnectionProvider(settings: settings, idleTimeout: .seconds(3600), sweepInterval: nil)
        defer { provider.shutdown() }
        #expect { _ = try provider.acquire(Self.endpoint) } throws: { isInitializationError($0) }
    }

    @Test("An unreadable file makes the client refuse to connect even without TLS")
    func refusesToConnectEvenWhenInsecure() {
        let settings = ClientSettings.localhost().secure(false).certificate(path: missingPath)
        let provider = ConnectionProvider(settings: settings, idleTimeout: .seconds(3600), sweepInterval: nil)
        defer { provider.shutdown() }
        #expect { _ = try provider.acquire(Self.endpoint) } throws: { isInitializationError($0) }
    }

    @Test("An unreadable file never turns into the system trust roots")
    func neverFallsBackToSystemRoots() {
        let settings = ClientSettings.localhost().secure(true).certificate(path: missingPath)
        guard case let .certificates(certificates)? = settings.trustRoots else {
            Issue.record("expected .certificates, got \(String(describing: settings.trustRoots))")
            return
        }
        #expect(certificates.isEmpty)
    }

    @Test("The unreadable file stays recorded after another CA is added")
    func unreadableStaysRecordedAfterAnotherCertificate() throws {
        let settings = ClientSettings.localhost().secure(true)
            .certificate(path: missingPath)
            .certificate(source: .file(path: try temporaryFile(Self.pem), format: .pem))
        guard case let .certificates(certificates)? = settings.trustRoots else {
            Issue.record("expected .certificates")
            return
        }
        #expect(certificates.count == 1)
        let provider = ConnectionProvider(settings: settings, idleTimeout: .seconds(3600), sweepInterval: nil)
        defer { provider.shutdown() }
        #expect { _ = try provider.acquire(Self.endpoint) } throws: { isInitializationError($0) }
    }

    @Test("A readable file behaves as before")
    func readableFileUnchanged() throws {
        let settings = ClientSettings.localhost().secure(true).certificate(path: try temporaryFile(Self.pem))
        #expect(!settings.hasUnreadableCertificate)
        guard case let .certificates(certificates)? = settings.trustRoots else {
            Issue.record("expected .certificates")
            return
        }
        #expect(certificates.count == 1)
    }

    @Test("The refusal is not retried as a node failure")
    func refusalIsNotANodeFailure() {
        #expect(!KurrentError.initializationError(reason: "x").isNodeFailure)
    }
}
```

These tests call the deprecated method on purpose; the deprecation warnings they produce in the test target are expected.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift build --build-tests 2>&1 | grep -E "error:" | head -3`
Expected: compile error — `hasUnreadableCertificate` not found.

- [ ] **Step 3: Implement**

(a) In `ClientSettings`, after `public var certificates: [TLSConfig.CertificateSource]`, add:

```swift
    /// Set by the deprecated ``certificate(path:)`` when its file cannot be read. The client then
    /// refuses to connect and ``trustRoots`` never falls back to the system roots.
    package var hasUnreadableCertificate: Bool = false
```

(b) Replace the body of `trustRoots`:

```swift
    public var trustRoots: TLSConfig.TrustRootsSource? {
        guard secure else {
            return nil
        }
        // A CA that was named but could not be read must not become "trust the system roots".
        return if certificates.isEmpty && !hasUnreadableCertificate {
            .systemDefault
        } else {
            .certificates(certificates)
        }
    }
```

(c) Replace `certificate(path:)` (keep its position):

```swift
    /// Returns a copy with a certificate loaded from the given file path appended.
    ///
    /// When the file cannot be read it is not silently replaced by the system trust roots: the
    /// client refuses to connect with `KurrentError.initializationError`.
    ///
    /// - Parameter path: File-system path to the certificate file.
    @available(*, deprecated, message: "Use certificate(path:fallback:), which reports an unreadable file instead of widening trust.")
    @discardableResult
    public func certificate(path: String) -> Self {
        withCopy {
            if let certificate = Self.readableCertificate(path: path) {
                $0.certificates.append(certificate)
            } else {
                $0.hasUnreadableCertificate = true
            }
        }
    }
```

Also change the deprecated `cerificate(path:)` attribute from `renamed: "certificate(path:)"` to `message: "Use certificate(path:fallback:)."` so it no longer points at a deprecated API.

(d) In `Sources/KurrentDB/Core/ConnectionProvider.swift`, at the top of `private func makeClient(for endpoint: Endpoint) throws(KurrentError) -> Client`, before `let settings = settings`, add:

```swift
        // The deprecated certificate(path:) could not read its CA. Refuse rather than connect
        // with a trust set the caller did not ask for.
        guard !settings.hasUnreadableCertificate else {
            throw .initializationError(reason: "A CA certificate file passed to certificate(path:) cannot be read; refusing to fall back to the system trust roots.")
        }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift build --build-tests 2>&1 | grep -E "error:|Build complete" | head -3 && swift test --skip-build --no-parallel --disable-xctest --enable-swift-testing --filter "LegacyCertificatePathTests|CertificateFallbackTests|ConnectionProviderTests|ClientSettingsParsingTests" 2>&1 | grep -E "✘|Test run with"`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/KurrentDB/Core/ClientSettings/ClientSettings.swift Sources/KurrentDB/Core/ConnectionProvider.swift Tests/MockClientTests/LegacyCertificatePathTests.swift
git commit -m "[FIX] deprecate certificate(path:) and refuse to connect when its CA cannot be read"
```

---

### Task 3: Documentation and full verification

**Files:**
- Modify: `README.md` (the "Local development — multi-node TLS cluster" example, ~line 72–77)
- Modify: `Sources/KurrentDB/KurrentDB.docc/Articles/Getting started.md` (the `tlsCaFile` row ~line 66; the builder table ~line 192)

- [ ] **Step 1: README example**

Replace

```swift
let localCluster = ClientSettings.localhost(ports: 2111, 2112, 2113)
    .secure(true)
    .tlsVerifyCert(false)
    .authenticated(.credentials(username: "admin", password: "changeit"))
    .certificate(path: "/path/to/ca.crt")
```

with

```swift
let localCluster = try ClientSettings.localhost(ports: 2111, 2112, 2113)
    .secure(true)
    .tlsVerifyCert(false)
    .authenticated(.credentials(username: "admin", password: "changeit"))
    .certificate(path: "/path/to/ca.crt", fallback: .none)
```

- [ ] **Step 2: Getting started**

(a) In the `tlsCaFile` row, append to the description: ` If the file cannot be read, `parse` throws instead of trusting the system's root certificates.`

(b) In the builder table replace the `.certificate(path:)` row with:

```
| `.certificate(path:fallback:)` | Add a CA certificate from a file. `fallback: .none` throws when the file cannot be read; `fallback: .systemTrustRoots` leaves it out and trusts the system roots instead (only for configurations shared with environments that legitimately have no CA file) |
```

- [ ] **Step 3: Check for remaining uses of the deprecated API in docs and snippets**

Run: `grep -rn "certificate(path: \"[^\"]*\")" README.md Sources/KurrentDB/KurrentDB.docc Sources/KurrentDB --include='*.md' --include='*.swift' | grep -v "fallback:"`
Expected: no output (doc comments of the deprecated method itself may mention `certificate(path:)` without a string literal and are fine).

- [ ] **Step 4: Compile the documentation examples**

Run: `scripts/check-doc-snippets.sh > /tmp/snippets.log 2>&1; echo "exit=$?"; grep -c "deprecated" /tmp/snippets.log`
Expected: `exit=0`, and no deprecation warning originating from `DocSnippets.generated.swift`.

- [ ] **Step 5: Full suite against the local cluster**

Run: `docker compose -f server/docker-compose.yaml up -d` (if not running), then `swift test --no-parallel --disable-xctest --enable-swift-testing 2>&1 | grep -E "✘|Test run with"`
Expected: no `✘`; paste every `Test run with` line in the report.

- [ ] **Step 6: Swift 6.0 Linux**

```bash
W=$(mktemp -d)/wt; git worktree add -q "$W" HEAD
docker run --rm --platform linux/arm64 -v "$W":/w -w /w swift:6.0-jammy swift test --no-parallel --disable-xctest --enable-swift-testing --filter "CertificateFallbackTests|LegacyCertificatePathTests|ClientSettingsParsingTests"
git worktree remove --force "$W"
```
Expected: pass (`parseRejectsUnreadableFile` is skipped there because the container runs as root).

- [ ] **Step 7: Commit**

```bash
git add README.md "Sources/KurrentDB/KurrentDB.docc/Articles/Getting started.md"
git commit -m "[UPDATE] document certificate(path:fallback:) and the strict tlsCaFile behaviour"
```

---

## Self-Review

- Spec §2 decisions → Task 1 (parse/fromEnv strict, new builder), Task 2 (deprecated builder records and refuses).
- Spec §3 API → Task 1 Step 3–4 (enum, no default, enum not struct), Task 2 Step 3c (deprecation message).
- Spec §4.1 → Task 1 Step 4b + `parseRejects*` tests (missing, empty, directory, permission) and path-not-echoed assertion; `fromEnv` goes through `parse`.
- Spec §4.2 → Task 1 Step 4c + `none*` / `systemTrustRoots*` tests.
- Spec §4.3 → Task 2 (flag, `trustRoots` guard, `makeClient` refusal, not a node failure).
- Spec §4.4 → `parseCertificate(path:)` untouched (Task 1 only adds a sibling helper).
- Spec §5 docs → Task 3; release notes go into the PR description.
- Spec §6 tests → covered across Tasks 1–2; snippets in Task 3.
- Names consistent: `CertificateFallback.none/.systemTrustRoots`, `certificate(path:fallback:)`, `readableCertificate(path:)`, `hasUnreadableCertificate`.
