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
        // `TLSConfig.TrustRootsSource.certificates` is a factory, not an enum case, so it cannot be
        // pattern-matched: a non-nil, non-system trust-roots source means "exactly these certificates".
        guard settings.trustRoots != nil, !isSystemDefault(settings) else { return nil }
        return settings.certificates.count
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
