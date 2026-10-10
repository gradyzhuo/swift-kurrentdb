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
        #expect(settings.trustRoots == .certificates([]))
        #expect(settings.trustRoots != .systemDefault)
    }

    @Test("The unreadable file stays recorded after another CA is added")
    func unreadableStaysRecordedAfterAnotherCertificate() throws {
        let settings = ClientSettings.localhost().secure(true)
            .certificate(path: missingPath)
            .certificate(source: .file(path: try temporaryFile(Self.pem), format: .pem))
        #expect(settings.certificates.count == 1)
        #expect(settings.trustRoots == .certificates(settings.certificates))
        let provider = ConnectionProvider(settings: settings, idleTimeout: .seconds(3600), sweepInterval: nil)
        defer { provider.shutdown() }
        #expect { _ = try provider.acquire(Self.endpoint) } throws: { isInitializationError($0) }
    }

    @Test("A readable file behaves as before")
    func readableFileUnchanged() throws {
        let settings = ClientSettings.localhost().secure(true).certificate(path: try temporaryFile(Self.pem))
        #expect(!settings.hasUnreadableCertificate)
        #expect(settings.certificates.count == 1)
        #expect(settings.trustRoots == .certificates(settings.certificates))
    }

    @Test("The refusal is not retried as a node failure")
    func refusalIsNotANodeFailure() {
        #expect(!KurrentError.initializationError(reason: "x").isNodeFailure)
    }
}
