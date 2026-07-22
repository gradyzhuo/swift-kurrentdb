//
//  AuthenticationTests.swift
//  swift-kurrentdb
//

import Foundation
import GRPCCore
@testable import KurrentDB
import Testing

@Suite("Authentication header Tests")
struct AuthenticationTests {
    @Test("credentials produces a Basic Authorization header")
    func basic() throws {
        let header = try Authentication.credentials(username: "admin", password: "changeit").makeAuthHeader()
        let expected = "Basic " + Data("admin:changeit".utf8).base64EncodedString()
        #expect(header == expected)
    }

    @Test("bearer produces a Bearer Authorization header")
    func bearer() throws {
        let header = try Authentication.bearer(token: "header.payload.signature").makeAuthHeader()
        #expect(header == "Bearer header.payload.signature")
    }

    @Test("x509 does not produce an Authorization header")
    func x509HasNoHeader() {
        #expect(throws: KurrentError.self) {
            _ = try Authentication.x509(certFile: "cert.pem", keyFile: "key.pem").makeAuthHeader()
        }
    }

    @Test("bearer description hides the token")
    func bearerDescriptionRedactsToken() {
        #expect(Authentication.bearer(token: "super-secret").description == "bearer(token: ***)")
    }
}

@Suite("Request metadata authentication Tests")
struct MetadataAuthenticationTests {
    /// Case-insensitive lookup, since gRPC metadata normalises header names.
    private func authorizationHeader(of metadata: Metadata) -> String? {
        for (key, value) in metadata where key.lowercased() == "authorization" {
            if case let .string(header) = value { return header }
        }
        return nil
    }

    private var settings: ClientSettings {
        .localhost().authenticated(.credentials(username: "admin", password: "changeit"))
    }

    @Test("per-call credentials replace the client-level Authorization header")
    func overrideReplacesClientLevelHeader() throws {
        let metadata = try Metadata(from: settings, overriding: .bearer(token: "token"))
        #expect(authorizationHeader(of: metadata) == "Bearer token")
    }

    @Test("client-level authentication is used when there is no override")
    func clientLevelHeaderUsedWithoutOverride() throws {
        let metadata = try Metadata(from: settings)
        let expected = "Basic " + Data("admin:changeit".utf8).base64EncodedString()
        #expect(authorizationHeader(of: metadata) == expected)
    }

    @Test("per-call x509 is rejected instead of silently falling back")
    func perCallX509IsRejected() {
        // mTLS identity is bound to the TLS connection, so it cannot be swapped per request.
        // Silently keeping the client-level identity would mislead the caller.
        #expect(throws: KurrentError.self) {
            _ = try Metadata(from: settings, overriding: .x509(certFile: "cert.pem", keyFile: "key.pem"))
        }
    }

    @Test("client-level x509 yields metadata with no Authorization header")
    func clientLevelX509OmitsHeader() throws {
        let x509Settings = ClientSettings.localhost().authenticated(.x509(certFile: "cert.pem", keyFile: "key.pem"))
        let metadata = try Metadata(from: x509Settings)
        #expect(authorizationHeader(of: metadata) == nil)
    }
}

@Suite("Consistency check revision encoding Tests")
struct ConsistencyCheckRevisionTests {
    @Test("lifecycle states map to the v2 constants")
    func lifecycleConstants() throws {
        #expect(try StreamRevision.any.v2ExpectedState() == -2)
        #expect(try StreamRevision.noStream.v2ExpectedState() == -1)
        #expect(try StreamRevision.streamExists.v2ExpectedState() == -4)
    }

    @Test("a concrete revision is encoded as-is")
    func concreteRevision() throws {
        #expect(try StreamRevision.at(7).v2ExpectedState() == 7)
        #expect(try StreamRevision.at(UInt64(Int64.max)).v2ExpectedState() == Int64.max)
    }

    @Test("a revision beyond Int64.max throws instead of trapping")
    func revisionOverflowThrows() {
        #expect(throws: KurrentError.self) {
            _ = try StreamRevision.at(UInt64(Int64.max) + 1).v2ExpectedState()
        }
        #expect(throws: KurrentError.self) {
            _ = try StreamRevision.at(UInt64.max).v2ExpectedState()
        }
    }
}
