//
//  AuthenticationTests.swift
//  swift-kurrentdb
//

import Foundation
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
