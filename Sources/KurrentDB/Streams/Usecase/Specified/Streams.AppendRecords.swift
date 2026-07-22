//
//  Streams.AppendRecords.swift
//  swift-kurrentdb
//
//  v2 AppendRecords — atomic multi-stream append with cross-stream consistency checks (DCB).
//

import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix
import SwiftProtobuf

extension Streams {
    /// Usecase that appends records to one or more streams atomically with cross-stream
    /// consistency checks (Dynamic Consistency Boundary). Requires KurrentDB 25.1+.
    ///
    /// Consistency checks are evaluated before any records are written. If any check fails, no
    /// records are written and every failing check is reported together via
    /// ``KurrentError/consistencyViolation(violations:)``.
    public struct AppendRecords: UnaryUnary {
        package typealias ServiceClient = Kurrentdb_Protocol_V2_Streams_StreamsService.Client<HTTP2ClientTransport.Posix>
        package typealias UnderlyingRequest = Kurrentdb_Protocol_V2_Streams_StreamsService.Method.AppendRecords.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.AppendRecords.Output

        package var methodDescriptor: GRPCCore.MethodDescriptor {
            ServiceClient.UnderlyingService.Method.AppendRecords.descriptor
        }

        package static var name: String {
            "Streams.\(Self.self)"
        }

        /// Stream events to write across one or more target streams.
        public let streamEvents: [StreamEvent]
        /// Explicit pre-commit consistency checks; may reference streams not written to.
        public let checks: [ConsistencyCheck]

        init(streamEvents: [StreamEvent], checks: [ConsistencyCheck]) {
            self.streamEvents = streamEvents
            self.checks = checks
        }

        /// Combines explicit ``checks`` with per-``StreamEvent`` expected revisions.
        ///
        /// Each `StreamEvent` whose `expectedRevision` is not `.any` contributes an implicit
        /// `StreamStateCheck` on its own stream, mirroring the .NET `(stream, expectedState, events)`
        /// overload. Explicit ``checks`` are appended after and may target any stream.
        private var resolvedChecks: [ConsistencyCheck] {
            let derived = streamEvents.compactMap { streamEvent -> ConsistencyCheck? in
                if case .any = streamEvent.expectedRevision { return nil }
                return .init(stream: streamEvent.streamIdentifier, expectedState: streamEvent.expectedRevision)
            }
            return derived + checks
        }

        package func requestMessage() throws -> UnderlyingRequest {
            try .with { request in
                request.records = streamEvents.flatMap { streamEvent in
                    streamEvent.records.map { record in
                        Kurrentdb_Protocol_V2_Streams_AppendRecord.with {
                            if let recordId = record.id {
                                $0.recordID = recordId.uuidString
                            }
                            $0.stream = streamEvent.streamIdentifier.name
                            $0.data = record.data
                            $0.properties = record.properties.structValue.fields
                            $0.schema = .with {
                                $0.name = record.schema.name
                                $0.format = .init(rawValue: record.schema.format.rawValue) ?? .unspecified
                            }
                        }
                    }
                }
                request.checks = try resolvedChecks.map { check in
                    try Kurrentdb_Protocol_V2_Streams_ConsistencyCheck.with {
                        $0.streamState = try .with {
                            $0.stream = check.streamIdentifier.name
                            $0.expectedState = try check.expectedState.v2ExpectedState()
                        }
                    }
                }
            }
        }

        package func send(connection: GRPCClient<Transport>, request: GRPCCore.ClientRequest<UnderlyingRequest>, callOptions: GRPCCore.CallOptions) async throws -> Response {
            let client = ServiceClient(wrapping: connection)
            return try await client.appendRecords(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}

extension Streams.AppendRecords {
    /// Resulting revision for a single stream that received records.
    public struct StreamAppendResult: Sendable {
        /// The stream that received records.
        public let streamIdentifier: StreamIdentifier
        /// The stream's revision after the append.
        public let revision: UInt64

        fileprivate init(streamIdentifier: StreamIdentifier, revision: UInt64) {
            self.streamIdentifier = streamIdentifier
            self.revision = revision
        }
    }

    /// Response returned after a successful AppendRecords transaction.
    public struct Response: GRPCResponse {
        package typealias UnderlyingMessage = UnderlyingResponse

        /// Resulting revision per stream that received records (no guaranteed order).
        public let revisions: [StreamAppendResult]
        /// Global commit position of the last record written in this transaction.
        public let position: StreamPosition

        init(revisions: [StreamAppendResult], position: StreamPosition) {
            self.revisions = revisions
            self.position = position
        }

        package init(from message: UnderlyingMessage) throws(KurrentError) {
            revisions = message.revisions.map {
                .init(streamIdentifier: .init(name: $0.stream), revision: UInt64($0.revision))
            }
            position = .at(commitPosition: UInt64(message.position))
        }
    }
}
