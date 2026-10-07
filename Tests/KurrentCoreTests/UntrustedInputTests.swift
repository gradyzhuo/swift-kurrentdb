//
//  UntrustedInputTests.swift
//  KurrentCoreTests
//
//  Inputs the SDK does not control — server responses, credentials, connection strings — must
//  fail as KurrentError, never terminate the process, send a request anonymously, or leak secrets
//  into error text. Each test pins one finding of the 2026-10-04 security audit (S04, S05, S07).
//

import GRPCCore
@testable import KurrentDB
import Testing

@Suite("Untrusted input")
struct UntrustedInputTests {
    private func isParsingError(_ error: any Error) -> Bool {
        if case .internalParsingError = error as? KurrentError { return true }
        return false
    }

    // MARK: S04 — signed wire values

    @Test("AppendRecords: a negative revision from the server is a parsing error, not a trap")
    func appendRecordsNegativeRevision() {
        var message = Streams<SpecifiedStream>.AppendRecords.UnderlyingResponse()
        message.revisions = [.with { $0.stream = "s"; $0.revision = -1 }]
        message.position = 10
        #expect { _ = try Streams<SpecifiedStream>.AppendRecords.Response(from: message) } throws: { isParsingError($0) }
    }

    @Test("AppendRecords: a negative position from the server is a parsing error, not a trap")
    func appendRecordsNegativePosition() {
        var message = Streams<SpecifiedStream>.AppendRecords.UnderlyingResponse()
        message.revisions = [.with { $0.stream = "s"; $0.revision = 3 }]
        message.position = .min
        #expect { _ = try Streams<SpecifiedStream>.AppendRecords.Response(from: message) } throws: { isParsingError($0) }
    }

    @Test("AppendRecords: valid values decode unchanged")
    func appendRecordsValid() throws {
        var message = Streams<SpecifiedStream>.AppendRecords.UnderlyingResponse()
        message.revisions = [.with { $0.stream = "s"; $0.revision = 3 }]
        message.position = .max
        let response = try Streams<SpecifiedStream>.AppendRecords.Response(from: message)
        #expect(response.revisions.first?.revision == 3)
        #expect(response.position == .at(commitPosition: UInt64(Int64.max)))
    }

    @Test("AppendSession: negative revision, per-stream position or session position is a parsing error")
    func appendSessionNegativeValues() {
        func message(revision: Int64 = 1, streamPosition: Int64? = 5, position: Int64 = 5) -> Streams<SpecifiedStream>.AppendSession.UnderlyingResponse {
            var message = Streams<SpecifiedStream>.AppendSession.UnderlyingResponse()
            message.output = [.with {
                $0.stream = "s"
                $0.streamRevision = revision
                if let streamPosition { $0.position = streamPosition }
            }]
            message.position = position
            return message
        }
        #expect { _ = try Streams<SpecifiedStream>.AppendSession.Response(from: message(revision: -1)) } throws: { isParsingError($0) }
        #expect { _ = try Streams<SpecifiedStream>.AppendSession.Response(from: message(streamPosition: -1)) } throws: { isParsingError($0) }
        #expect { _ = try Streams<SpecifiedStream>.AppendSession.Response(from: message(position: -1)) } throws: { isParsingError($0) }
        #expect(throws: Never.self) { _ = try Streams<SpecifiedStream>.AppendSession.Response(from: message(streamPosition: nil)) }
    }

    // MARK: S07 — credentials that cannot be encoded

    @Test("Credentials that cannot be encoded fail the request instead of sending it without Authorization")
    func nonASCIICredentialsThrow() {
        let settings = ClientSettings.localhost().authenticated(.credentials(username: "user", password: "密碼"))
        #expect {
            _ = try Metadata(from: settings)
        } throws: { error in
            if case .encodingError = error as? KurrentError { return true }
            return false
        }
        #expect {
            _ = try Metadata(from: .localhost(), overriding: .credentials(username: "使用者", password: "x"))
        } throws: { error in
            if case .encodingError = error as? KurrentError { return true }
            return false
        }
    }

    @Test("ASCII credentials still produce a Basic Authorization header")
    func asciiCredentialsProduceHeader() throws {
        let settings = ClientSettings.localhost().authenticated(.credentials(username: "admin", password: "changeit"))
        let metadata = try Metadata(from: settings)
        #expect(Array(metadata[stringValues: "Authorization"]) == ["Basic YWRtaW46Y2hhbmdlaXQ="])
    }

    // MARK: S05 — secrets in error text

    @Test("An unknown or missing scheme error does not echo the connection string")
    func schemeErrorDoesNotLeakCredentials() {
        for connectionString in ["mysql://admin:s3cr3t-pa55@localhost:2113", "admin:s3cr3t-pa55@localhost:2113"] {
            do {
                _ = try ClientSettings.parse(connectionString: connectionString)
                Issue.record("\(connectionString) parsed")
            } catch {
                #expect(!"\(error)".contains("s3cr3t-pa55"))
                #expect(!error.localizedDescription.contains("s3cr3t-pa55"))
            }
        }
    }
}
