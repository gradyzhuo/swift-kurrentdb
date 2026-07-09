//
//  KurrentError+ConsistencyViolation.swift
//  swift-kurrentdb
//
//  Decodes v2 AppendRecords consistency-violation error details from a gRPC status.
//

import Foundation
import GRPCCore
import GRPCEncapsulates
import GRPCProtobuf
import SwiftProtobuf

extension KurrentError {
    /// A single failed pre-commit consistency check reported by ``Streams/AppendRecords``.
    public struct ConsistencyViolation: Sendable, Equatable, CustomStringConvertible {
        /// Index of the failing check in the request's `checks` array.
        public let checkIndex: Int
        /// The stream whose state failed the check.
        public let stream: String
        /// The revision/state the check expected (v2 `expected_state` encoding).
        public let expectedState: Int64
        /// The actual current revision/state of the stream at evaluation time.
        public let actualState: Int64

        package init(checkIndex: Int, stream: String, expectedState: Int64, actualState: Int64) {
            self.checkIndex = checkIndex
            self.stream = stream
            self.expectedState = expectedState
            self.actualState = actualState
        }

        public var description: String {
            "check[\(checkIndex)] stream '\(stream)' expected \(expectedState) but was \(actualState)"
        }
    }
}

extension KurrentError {
    /// Builds a ``consistencyViolation(violations:)`` from a gRPC error's packed status details,
    /// or returns `nil` if the error does not carry AppendRecords consistency-violation details.
    static func consistencyViolation(from rpcError: RPCError) -> KurrentError? {
        guard let status = try? rpcError.unpackGoogleRPCStatus() else { return nil }

        for detail in status.details {
            guard let any = detail.any,
                  any.isA(Kurrentdb_Protocol_V2_Streams_Errors_AppendConsistencyViolationErrorDetails.self),
                  let payload = try? Kurrentdb_Protocol_V2_Streams_Errors_AppendConsistencyViolationErrorDetails(serializedBytes: any.value)
            else { continue }

            let violations = payload.violations.map { violation in
                let streamState = violation.streamState
                return ConsistencyViolation(
                    checkIndex: Int(violation.checkIndex),
                    stream: streamState.stream,
                    expectedState: streamState.expectedState,
                    actualState: streamState.actualState
                )
            }
            return .consistencyViolation(violations: violations)
        }

        return nil
    }
}
