//
//  KurrentError+WrongExpectedVersion.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2025/4/11.
//

import GRPCCore
import GRPCEncapsulates

extension KurrentError {
    /// Converts a protobuf `WrongExpectedVersion` response into a ``KurrentError/wrongExpectedVersion(expected:current:)`` case.
    package static func wrongExpectedVersion(_ wrongResult: EventStore_Client_Streams_AppendResp.WrongExpectedVersion) -> Self {
        let expectedRevision: ExpectedRevisionOption = wrongResult.expectedRevisionOption.map {
            switch $0 {
            case .expectedAny:
                .any
            case .expectedNoStream:
                .noStream
            case .expectedStreamExists:
                .streamExists
            case let .expectedRevision(revision):
                .revision(revision)
            }
        } ?? .any

        let currentRevision: CurrentRevisionOption = wrongResult.currentRevisionOption.map {
            switch $0 {
            case .currentNoStream:
                .noStream
            case let .currentRevision(revision):
                .revision(revision)
            }
        } ?? .noStream

        return .wrongExpectedVersion(expected: expectedRevision, current: currentRevision)
    }
}

extension KurrentError {
    /// Builds ``KurrentError/wrongExpectedVersion(expected:current:)`` from a delete or tombstone
    /// rejection, or returns `nil` when `rpcError` is not one.
    ///
    /// The server rejects these calls with an `exception: wrong-expected-version` trailer.
    /// `expected` is the caller's own request; only the server's `actual-version` trailer is read:
    /// `-1` when the stream does not exist, otherwise its revision. Any other value is left to the
    /// generic mapping instead of being guessed at.
    static func wrongExpectedVersion(from rpcError: RPCError, expected: StreamRevision) -> KurrentError? {
        let metadata = rpcError.metadata
        func firstValue(_ key: String) -> String? {
            var values = metadata[stringValues: key].makeIterator()
            return values.next()
        }
        guard firstValue("exception") == "wrong-expected-version",
              let actualText = firstValue("actual-version"),
              let actual = Int64(actualText)
        else {
            return nil
        }

        let expectation: ExpectedRevisionOption = switch expected {
        case .any: .any
        case .noStream: .noStream
        case .streamExists: .streamExists
        case let .at(revision): .revision(revision)
        }

        if actual == -1 {
            return .wrongExpectedVersion(expected: expectation, current: .noStream)
        }
        guard actual >= 0 else { return nil }
        return .wrongExpectedVersion(expected: expectation, current: .revision(UInt64(actual)))
    }
}
