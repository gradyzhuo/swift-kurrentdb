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
        let mapped = mapStreamError(streamDeleted("orders-1"), usage: "t")
        guard case let .resourceDeleted(resource)? = mapped as? KurrentError else {
            Issue.record("expected KurrentError.resourceDeleted, got \(mapped)")
            return
        }
        #expect(resource == "orders-1")
    }

    @Test("mapStreamError: RPC codes map like unary calls, KurrentError and CancellationError pass through, other errors are internal")
    func mapStreamErrorTable() {
        #expect(mapStreamError(RPCError(code: .deadlineExceeded, message: ""), usage: "t") as? KurrentError == .deadlineExceeded)
        #expect(mapStreamError(RPCError(code: .cancelled, message: ""), usage: "t") as? KurrentError == .connectionClosed)
        #expect(mapStreamError(RPCError(code: .permissionDenied, message: ""), usage: "t") as? KurrentError == .accessDenied)
        if case .grpcError? = mapStreamError(RPCError(code: .unknown, message: "x"), usage: "t") as? KurrentError {} else { Issue.record("unknown codes stay visible as grpcError") }
        #expect(mapStreamError(CancellationError(), usage: "t") is CancellationError)
        #expect(mapStreamError(KurrentError.accessDenied, usage: "t") as? KurrentError == .accessDenied)
        struct Other: Error, CustomStringConvertible { var description: String { "undecodable frame" } }
        if case let .internalClientError(reason)? = mapStreamError(Other(), usage: "t") as? KurrentError {
            #expect(reason.contains("undecodable frame"), "the reason keeps the original error: \(reason)")
        } else {
            Issue.record("foreign errors become internalClientError")
        }
    }

    @Test("A stream-deleted trailer wins over the status code, whichever side of acceptance it ends")
    func trailerWinsOverStatusCode() {
        // A status-only rejection (access denied, tombstoned stream) and a stream that ends after
        // acceptance go through the same table.
        if case .resourceDeleted("orders-1")? = mapStreamError(streamDeleted("orders-1"), usage: "t") as? KurrentError {} else {
            Issue.record("expected resourceDeleted")
        }
        #expect(mapStreamError(RPCError(code: .unauthenticated, message: "Access Denied"), usage: "t") as? KurrentError == .accessDenied)
        #expect(mapStreamError(RPCError(code: .internalError, message: "boom"), usage: "t") as? KurrentError == .serverError("boom"))
    }
}
