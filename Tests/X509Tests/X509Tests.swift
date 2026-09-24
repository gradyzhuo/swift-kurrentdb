//
//  X509Tests.swift
//  swift-kurrentdb
//
//  Authenticates with an X.509 user certificate against a live KurrentDB node.
//
//  User certificates are a licensed KurrentDB feature, so this suite needs the node
//  that `server/x509/start.sh` starts. Without KURRENTDB_X509_CERTS_DIR the suite
//  is skipped rather than failed.
//

import Foundation
import KurrentDB
import Testing

@Suite(
    "X.509 user certificate authentication",
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["KURRENTDB_X509_CERTS_DIR"] != nil)
)
struct X509Tests {
    let certs: String
    let host: String
    let port: String

    init() {
        let environment = ProcessInfo.processInfo.environment
        certs = environment["KURRENTDB_X509_CERTS_DIR"] ?? ""
        host = environment["KURRENTDB_X509_HOST"] ?? "127.0.0.1"
        port = environment["KURRENTDB_X509_PORT"] ?? "2116"
    }

    /// Connection string that trusts the test CA and presents the `admin` user certificate.
    var certificateSettings: ClientSettings {
        get throws {
            try .parse(connectionString: "kurrentdb://\(host):\(port)?tls=true&tlsCaFile=\(certs)/ca/ca.crt&userCertFile=\(certs)/user-admin/user.crt&userKeyFile=\(certs)/user-admin/user.key")
        }
    }

    /// The same node and CA, but no credentials at all.
    var anonymousSettings: ClientSettings {
        get throws {
            try .parse(connectionString: "kurrentdb://\(host):\(port)?tls=true&tlsCaFile=\(certs)/ca/ca.crt")
        }
    }

    @Test("reading $all is denied without credentials")
    func anonymousReadOfAllIsDenied() async throws {
        let client = try KurrentDBClient(settings: anonymousSettings)
        defer { try? client.shutdown() }

        await #expect(throws: KurrentError.accessDenied) {
            for try await _ in try await client.allStreams.read(configure: { $0.limit = 1 }) {}
        }
    }

    @Test("the admin user certificate is allowed to read $all")
    func certificateAuthenticatesAsAdmin() async throws {
        let client = try KurrentDBClient(settings: certificateSettings)
        defer { try? client.shutdown() }

        var count = 0
        for try await response in try await client.allStreams.read(configure: { $0.limit = 1 }) {
            _ = try response.event
            count += 1
        }
        #expect(count == 1)
    }

    @Test("appends and reads back a stream as the certificate user")
    func certificateUserCanWriteAndRead() async throws {
        let client = try KurrentDBClient(settings: certificateSettings)
        defer { try? client.shutdown() }

        let stream = client.streams(specified: "x509-\(UUID().uuidString)")
        try await stream.append(events: EventData(eventType: "X509Tested", model: ["by": "certificate"])) {
            $0.expectedRevision = .noStream
        }

        var eventTypes: [String] = []
        for try await response in try await stream.read() {
            try eventTypes.append(response.event.record.eventType)
        }
        #expect(eventTypes == ["X509Tested"])
    }
}
