//
//  KurrentError+StreamsErrorDetails.swift
//  swift-kurrentdb
//
//  Decodes the error details the v2 Streams service (AppendSession, AppendRecords) packs into a
//  gRPC status.
//

import Foundation
import GRPCCore
import GRPCEncapsulates
import GRPCProtobuf
import SwiftProtobuf

extension KurrentError {
    /// The domain error a v2 Streams call reported in its packed status details, or `nil` when
    /// `rpcError` carries none.
    ///
    /// The v2 service reports a tombstoned stream or a revision conflict with a status code
    /// (`FAILED_PRECONDITION`, `ABORTED`) that would otherwise map to ``grpcError(cause:)``, which
    /// counts as a node failure and is retried. Every error decoded here is a domain error, so it is
    /// neither retried nor treated as a node failure.
    static func streamsErrorDetails(from rpcError: RPCError) -> KurrentError? {
        guard let status = try? rpcError.unpackGoogleRPCStatus() else { return nil }

        var isStreamsDomain = false
        for detail in status.details {
            if let info = detail.errorInfo, info.domain == "streams" {
                isStreamsDomain = true
            }
            guard let any = detail.any else { continue }

            if let payload = unpack(Kurrentdb_Protocol_V2_Streams_Errors_StreamTombstonedErrorDetails.self, from: any) {
                return .resourceDeleted(resource: payload.stream)
            }
            if let payload = unpack(Kurrentdb_Protocol_V2_Streams_Errors_StreamDeletedErrorDetails.self, from: any) {
                return .resourceDeleted(resource: payload.stream)
            }
            if let payload = unpack(Kurrentdb_Protocol_V2_Streams_Errors_StreamRevisionConflictErrorDetails.self, from: any) {
                return .wrongExpectedVersion(
                    expected: .init(v2ExpectedRevision: payload.expectedRevision),
                    current: .init(v2ActualRevision: payload.actualRevision)
                )
            }
            if unpack(Kurrentdb_Protocol_V2_Streams_Errors_StreamNotFoundErrorDetails.self, from: any) != nil {
                return .resourceNotFound(reason: status.message)
            }
            if unpack(Kurrentdb_Protocol_V2_Streams_Errors_StreamAlreadyExistsErrorDetails.self, from: any) != nil {
                return .resourceAlreadyExists
            }
        }

        // Size limits, a stream appearing twice in one session, an empty session: the request
        // itself is at fault, so sending it again cannot succeed.
        return isStreamsDomain ? .illegalStateError(reason: status.message) : nil
    }

    private static func unpack<Details: SwiftProtobuf.Message>(_: Details.Type, from any: Google_Protobuf_Any) -> Details? {
        guard any.isA(Details.self) else { return nil }
        return try? Details(serializedBytes: any.value)
    }
}

extension KurrentError.ExpectedRevisionOption {
    /// The expected revision a v2 request sent, from its wire value.
    init(v2ExpectedRevision value: Int64) {
        switch value {
        case -1: self = .noStream
        case -4: self = .streamExists
        case 0...: self = .revision(UInt64(value))
        default: self = .any
        }
    }
}

extension KurrentError.CurrentRevisionState {
    /// The revision a v2 error reports a stream at; a negative value means it has no revision.
    init(v2ActualRevision value: Int64) {
        self = value >= 0 ? .revision(UInt64(value)) : .noStream
    }
}
