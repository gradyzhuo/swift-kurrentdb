//
//  RPCErrorMappingTests.swift
//  KurrentCoreTests
//

@testable import KurrentDB
import GRPCCore
import Testing

@Suite("RPCError.rethrow() gRPC status code mapping")
struct RPCErrorMappingTests {

    // Helper: invoke rethrow and capture the thrown KurrentError.
    private func mapped(_ rpcError: RPCError) -> KurrentError? {
        do throws(KurrentError) {
            try rpcError.rethrow(usage: "test")
            return nil
        } catch {
            return error
        }
    }

    // MARK: - Status code → KurrentError mapping

    @Test("deadlineExceeded → .deadlineExceeded")
    func testDeadlineExceeded() {
        let error = RPCError(code: .deadlineExceeded, message: "timeout")
        #expect(mapped(error) == .deadlineExceeded)
    }

    @Test("unauthenticated → .accessDenied")
    func testUnauthenticated() {
        let error = RPCError(code: .unauthenticated, message: "invalid credentials")
        #expect(mapped(error) == .accessDenied)
    }

    @Test("permissionDenied → .accessDenied")
    func testPermissionDenied() {
        let error = RPCError(code: .permissionDenied, message: "forbidden")
        #expect(mapped(error) == .accessDenied)
    }

    @Test("notFound → .resourceNotFound carrying the gRPC message")
    func testNotFound() {
        let error = RPCError(code: .notFound, message: "stream not found")
        #expect(mapped(error) == .resourceNotFound(reason: "stream not found"))
    }

    @Test("alreadyExists → .resourceAlreadyExists")
    func testAlreadyExists() {
        let error = RPCError(code: .alreadyExists, message: "already exists")
        #expect(mapped(error) == .resourceAlreadyExists)
    }

    @Test("unavailable → .grpcConnectionError")
    func testUnavailable() {
        let error = RPCError(code: .unavailable, message: "service unavailable")
        let result = mapped(error)
        if case .grpcConnectionError = result {
            // pass
        } else {
            Issue.record("Expected .grpcConnectionError, got \(String(describing: result))")
        }
    }

    @Test("cancelled → .connectionClosed")
    func testCancelled() {
        let error = RPCError(code: .cancelled, message: "cancelled by client")
        #expect(mapped(error) == .connectionClosed)
    }

    @Test("invalidArgument → .illegalStateError carrying the gRPC message")
    func testInvalidArgument() {
        let error = RPCError(code: .invalidArgument, message: "bad argument")
        #expect(mapped(error) == .illegalStateError(reason: "bad argument"))
    }

    @Test("outOfRange → .illegalStateError carrying the gRPC message")
    func testOutOfRange() {
        let error = RPCError(code: .outOfRange, message: "out of range")
        #expect(mapped(error) == .illegalStateError(reason: "out of range"))
    }

    @Test("internalError → .serverError carrying the gRPC message")
    func testInternalError() {
        let error = RPCError(code: .internalError, message: "internal failure")
        #expect(mapped(error) == .serverError("internal failure"))
    }

    @Test("dataLoss → .serverError carrying the gRPC message")
    func testDataLoss() {
        let error = RPCError(code: .dataLoss, message: "data lost")
        #expect(mapped(error) == .serverError("data lost"))
    }

    // MARK: - default: message content fallback

    @Test("unknown code with 'NotFound' in message → .resourceNotFound")
    func testMessageFallbackNotFound() {
        let error = RPCError(code: .unknown, message: "NotFound: projection does not exist")
        #expect(mapped(error) == .resourceNotFound(reason: "NotFound: projection does not exist"))
    }

    @Test("unknown code with 'Conflict' in message → .resourceAlreadyExists")
    func testMessageFallbackConflict() {
        let error = RPCError(code: .unknown, message: "Conflict: projection already exists")
        #expect(mapped(error) == .resourceAlreadyExists)
    }

    @Test("unknown code with 'AlreadyExists' in message → .resourceAlreadyExists")
    func testMessageFallbackAlreadyExists() {
        let error = RPCError(code: .unknown, message: "AlreadyExists: duplicate resource")
        #expect(mapped(error) == .resourceAlreadyExists)
    }

    @Test("unknown code with unrecognised message → .grpcError")
    func testMessageFallbackUnknown() {
        let error = RPCError(code: .unknown, message: "some unexpected error")
        let result = mapped(error)
        if case .grpcError = result {
            // pass
        } else {
            Issue.record("Expected .grpcError, got \(String(describing: result))")
        }
    }

    // MARK: - Metadata exception

    @Test("metadata exception 'stream-deleted' → .resourceDeleted with stream name")
    func testMetadataStreamDeleted() {
        var metadata = Metadata()
        metadata.addString("stream-deleted", forKey: "exception")
        metadata.addString("my-stream", forKey: "stream-name")
        let error = RPCError(code: .unknown, message: "stream deleted", metadata: metadata)
        if case .resourceDeleted(let resource) = mapped(error) {
            #expect(resource == "my-stream")
        } else {
            Issue.record("Expected .resourceDeleted")
        }
    }

    @Test("metadata exception 'stream-deleted' without stream-name → resource is 'unknown'")
    func testMetadataStreamDeletedNoName() {
        var metadata = Metadata()
        metadata.addString("stream-deleted", forKey: "exception")
        let error = RPCError(code: .unknown, message: "stream deleted", metadata: metadata)
        #expect(mapped(error) == .resourceDeleted(resource: "unknown"))
    }
}
