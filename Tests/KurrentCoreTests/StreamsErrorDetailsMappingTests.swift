//
//  StreamsErrorDetailsMappingTests.swift
//  KurrentCoreTests
//

import _GRPCProtobufGenerated
import GRPCCore
import GRPCProtobuf
@testable import KurrentDB
import SwiftProtobuf
import Testing

@Suite("v2 Streams error details mapping")
struct StreamsErrorDetailsMappingTests {
    /// An RPCError shaped like the v2 Streams service sends it: an ErrorInfo plus the packed details.
    private func streamsError(
        code: RPCError.Code,
        reason: String,
        message: String = "server message",
        details: (any SwiftProtobuf.Message)? = nil
    ) throws -> RPCError {
        var errorDetails: [ErrorDetails] = [.errorInfo(reason: reason, domain: "streams", metadata: [:])]
        if let details {
            errorDetails.append(try .any(Google_Protobuf_Any(message: details)))
        }
        let status = GoogleRPCStatus(code: code, message: message, details: errorDetails)
        let bytes: [UInt8] = try status.serializedBytes()
        return RPCError(code: code, message: message, metadata: ["grpc-status-details-bin": .binary(bytes)])
    }

    private func mapped(_ rpcError: RPCError) -> KurrentError? {
        do throws(KurrentError) {
            try rpcError.rethrow(usage: "test")
            return nil
        } catch {
            return error
        }
    }

    @Test("STREAM_TOMBSTONED → .resourceDeleted with the stream name, not retried")
    func tombstoned() throws {
        let error = try mapped(streamsError(
            code: .failedPrecondition, reason: "STREAM_TOMBSTONED",
            details: Kurrentdb_Protocol_V2_Streams_Errors_StreamTombstonedErrorDetails.with { $0.stream = "orders-1" }
        ))
        #expect(error == .resourceDeleted(resource: "orders-1"))
        #expect(error?.isNodeFailure == false)
    }

    @Test("STREAM_DELETED → .resourceDeleted with the stream name")
    func deleted() throws {
        let error = try mapped(streamsError(
            code: .failedPrecondition, reason: "STREAM_DELETED",
            details: Kurrentdb_Protocol_V2_Streams_Errors_StreamDeletedErrorDetails.with { $0.stream = "orders-2" }
        ))
        #expect(error == .resourceDeleted(resource: "orders-2"))
    }

    @Test("STREAM_REVISION_CONFLICT → .wrongExpectedVersion with both revisions")
    func revisionConflict() throws {
        let error = try mapped(streamsError(
            code: .failedPrecondition, reason: "STREAM_REVISION_CONFLICT",
            details: Kurrentdb_Protocol_V2_Streams_Errors_StreamRevisionConflictErrorDetails.with {
                $0.stream = "orders-3"
                $0.expectedRevision = 5
                $0.actualRevision = 0
            }
        ))
        guard case let .wrongExpectedVersion(expected, current) = error,
              case .revision(5) = expected, case .revision(0) = current
        else {
            Issue.record("Expected .wrongExpectedVersion(5, 0), got \(String(describing: error))")
            return
        }
        #expect(error?.isNodeFailure == false)
    }

    @Test("STREAM_REVISION_CONFLICT with the no-stream constants keeps them")
    func revisionConflictConstants() throws {
        let error = try mapped(streamsError(
            code: .failedPrecondition, reason: "STREAM_REVISION_CONFLICT",
            details: Kurrentdb_Protocol_V2_Streams_Errors_StreamRevisionConflictErrorDetails.with {
                $0.stream = "orders-4"
                $0.expectedRevision = -4
                $0.actualRevision = -1
            }
        ))
        guard case let .wrongExpectedVersion(expected, current) = error,
              case .streamExists = expected, case .noStream = current
        else {
            Issue.record("Expected .wrongExpectedVersion(.streamExists, .noStream), got \(String(describing: error))")
            return
        }
    }

    @Test("STREAM_ALREADY_IN_APPEND_SESSION (ABORTED) → .illegalStateError, not retried")
    func alreadyInSession() throws {
        let error = try mapped(streamsError(
            code: .aborted, reason: "STREAM_ALREADY_IN_APPEND_SESSION", message: "already in session",
            details: Kurrentdb_Protocol_V2_Streams_Errors_StreamAlreadyInAppendSessionErrorDetails.with { $0.stream = "s" }
        ))
        #expect(error == .illegalStateError(reason: "already in session"))
        #expect(error?.isNodeFailure == false)
    }

    @Test("A streams-domain error without details (APPEND_SESSION_NO_REQUESTS) → .illegalStateError")
    func noRequests() throws {
        let error = try mapped(streamsError(code: .failedPrecondition, reason: "APPEND_SESSION_NO_REQUESTS", message: "no requests"))
        #expect(error == .illegalStateError(reason: "no requests"))
    }

    @Test("Consistency violations still decode as .consistencyViolation")
    func consistencyViolationStillWins() throws {
        let error = try mapped(streamsError(
            code: .failedPrecondition, reason: "APPEND_CONSISTENCY_VIOLATION",
            details: Kurrentdb_Protocol_V2_Streams_Errors_AppendConsistencyViolationErrorDetails.with {
                $0.violations = [.with {
                    $0.checkIndex = 0
                    $0.streamState = .with { $0.stream = "s"; $0.expectedState = -1; $0.actualState = -6 }
                }]
            }
        ))
        guard case let .consistencyViolation(violations) = error else {
            Issue.record("Expected .consistencyViolation, got \(String(describing: error))")
            return
        }
        #expect(violations == [.init(checkIndex: 0, stream: "s", expectedState: -1, actualState: -6)])
    }

    @Test("A status from another domain still falls through to the status-code mapping")
    func otherDomain() throws {
        let status = GoogleRPCStatus(code: .failedPrecondition, message: "m", details: [.errorInfo(reason: "X", domain: "other", metadata: [:])])
        let bytes: [UInt8] = try status.serializedBytes()
        let error = mapped(RPCError(code: .failedPrecondition, message: "m", metadata: ["grpc-status-details-bin": .binary(bytes)]))
        guard case .grpcError = error else {
            Issue.record("Expected .grpcError, got \(String(describing: error))")
            return
        }
    }
}
