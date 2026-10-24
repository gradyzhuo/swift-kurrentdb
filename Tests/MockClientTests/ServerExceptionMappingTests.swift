//
//  ServerExceptionMappingTests.swift
//  MockClientTests
//

import GRPCCore
import Testing
@testable import KurrentDB

@Suite("Server exception mapping for streamed responses")
struct ServerExceptionMappingTests {
    private func streamDeleted(_ name: String) -> RPCError {
        var metadata = Metadata()
        metadata.addString("stream-deleted", forKey: "exception")
        metadata.addString(name, forKey: "stream-name")
        return RPCError(code: .failedPrecondition, message: "Event stream '\(name)' is deleted.", metadata: metadata)
    }

    @Test("A stream-deleted trailer becomes resourceDeleted")
    func mapsStreamDeleted() {
        let mapped = serverExceptionOrOriginal(streamDeleted("orders-1"))
        guard case let .resourceDeleted(resource)? = mapped as? KurrentError else {
            Issue.record("expected KurrentError.resourceDeleted, got \(mapped)")
            return
        }
        #expect(resource == "orders-1")
    }

    @Test("An RPC error without a server exception passes through unchanged")
    func keepsDeadline() {
        // Post-acceptance deadlines reach a read's consumer as the RPC's own error (LazyReadLiveTests).
        let mapped = serverExceptionOrOriginal(RPCError(code: .deadlineExceeded, message: "RPC timed out"))
        #expect((mapped as? RPCError)?.code == .deadlineExceeded)
    }

    @Test("Non-RPC errors pass through unchanged")
    func keepsOtherErrors() {
        #expect(serverExceptionOrOriginal(CancellationError()) is CancellationError)
        if case .connectionClosed? = serverExceptionOrOriginal(KurrentError.connectionClosed) as? KurrentError {} else {
            Issue.record("expected KurrentError.connectionClosed to pass through")
        }
    }

    @Test("A rejected buffered read is mapped like any rejected call")
    func rejectedReadIsFullyMapped() {
        let denied = bufferedReadFailure(RPCError(code: .permissionDenied, message: "Access Denied"), rejected: true)
        if case .accessDenied? = denied as? KurrentError {} else { Issue.record("expected accessDenied, got \(denied)") }

        let deleted = bufferedReadFailure(streamDeleted("orders-1"), rejected: true)
        if case .resourceDeleted("orders-1")? = deleted as? KurrentError {} else { Issue.record("expected resourceDeleted, got \(deleted)") }
    }

    @Test("After acceptance a buffered read maps only server exceptions")
    func acceptedReadMapsOnlyServerExceptions() {
        let denied = bufferedReadFailure(RPCError(code: .permissionDenied, message: "Access Denied"), rejected: false)
        #expect((denied as? RPCError)?.code == .permissionDenied)

        let deadline = bufferedReadFailure(RPCError(code: .deadlineExceeded, message: "RPC timed out"), rejected: false)
        #expect((deadline as? RPCError)?.code == .deadlineExceeded)

        let deleted = bufferedReadFailure(streamDeleted("orders-1"), rejected: false)
        if case .resourceDeleted? = deleted as? KurrentError {} else { Issue.record("expected resourceDeleted, got \(deleted)") }
    }
}
