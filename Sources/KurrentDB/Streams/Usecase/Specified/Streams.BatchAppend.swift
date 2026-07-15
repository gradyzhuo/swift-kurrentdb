//
//  Streams.BatchAppend.swift
//  swift-kurrentdb
//
//  v1 BatchAppend — pipelines multiple independent appends over one bidi call.
//  Non-atomic: each item succeeds or fails on its own.
//

import Foundation
import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix
import NIO

extension Streams {
    /// Usecase that pipelines multiple appends (potentially to different streams) over a single
    /// bidirectional `BatchAppend` call. Unlike ``Append``/``AppendSession`` this is **non-atomic**:
    /// each item is an independent append and returns its own success/failure.
    public struct BatchAppend: Usecase, StreamRequestBuildable, Sendable {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.BatchAppend.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.BatchAppend.Output

        package var methodDescriptor: GRPCCore.MethodDescriptor {
            ServiceClient.UnderlyingService.Method.BatchAppend.descriptor
        }

        package static var name: String {
            "Streams.\(Self.self)"
        }

        /// Append operations to pipeline, each carrying its target stream and expected revision.
        public let streamEvents: [StreamEvent]
        /// One SDK-generated correlation id per item, used to route responses back to inputs.
        private let correlationIds: [UUID]

        init(streamEvents: [StreamEvent]) {
            self.streamEvents = streamEvents
            correlationIds = streamEvents.map { _ in UUID() }
        }

        package func requestMessages() throws -> [UnderlyingRequest] {
            try zip(streamEvents, correlationIds).map { streamEvent, correlationId in
                try UnderlyingRequest.with { request in
                    request.correlationID = correlationId.toEventStoreUUID()
                    request.options = try .with { options in
                        options.streamIdentifier = try streamEvent.streamIdentifier.build()
                        switch streamEvent.expectedRevision {
                        case .any:
                            options.any = .init()
                        case .noStream:
                            options.noStream = .init()
                        case .streamExists:
                            options.streamExists = .init()
                        case let .at(revision):
                            options.streamPosition = revision
                        }
                    }
                    request.proposedMessages = streamEvent.records.map { record in
                        .with { message in
                            // BatchAppend requires a non-empty message id; generate one when the
                            // record does not carry its own.
                            message.id = (record.id ?? UUID()).toEventStoreUUID()
                            message.data = record.data
                            let contentType = record.schema.format == .json ? "application/json" : "application/octet-stream"
                            message.metadata = [
                                "type": record.schema.name,
                                "content-type": contentType,
                            ]
                            if !record.properties.isEmpty,
                               JSONSerialization.isValidJSONObject(record.properties),
                               let customData = try? JSONSerialization.data(withJSONObject: record.properties) {
                                message.customMetadata = customData
                            }
                        }
                    }
                    request.isFinal = true
                }
            }
        }

        package func perform(selector: NodeSelector, callOptions: CallOptions) async throws(KurrentError) -> Response {
            try await withRetry(
                policy: selector.retryPolicy,
                selectNode: { try await selector.select() },
                invalidate: { await selector.invalidate() }
            ) { node in
                try await perform(node: node, callOptions: callOptions)
            }
        }

        package func perform(node: Node, callOptions: CallOptions) async throws(KurrentError) -> Response {
            guard node.serverInfo.isSupported(method: methodDescriptor) else {
                throw .unsupportedFeature(methodDescriptor)
            }

            let client = try GRPCClient<HTTP2ClientTransport.Posix>(from: node)
            Task {
                logger.debug("[\(Self.name)] Opening connection...")
                try await client.runConnections()
            }

            defer {
                logger.debug("[\(Self.name)] Closing connection...")
                client.beginGracefulShutdown()
            }

            let eventByCorrelation = Dictionary(uniqueKeysWithValues: zip(correlationIds, streamEvents))

            return try await withRethrowingError(usage: "\(Self.self).\(#function)") {
                let metadata = Metadata(from: node.settings)
                let messages = try requestMessages()
                let serviceClient = ServiceClient(wrapping: client)

                // BatchAppend is designed for a long-lived multiplexing call: the server only serves
                // additional items while the request stream stays open, and closes the response
                // stream once the request half-closes. So keep the request open until every item has
                // a result, then release it.
                let (keepOpen, releaseRequest) = AsyncStream<Void>.makeStream()
                let request = StreamingClientRequest(metadata: metadata) { writer in
                    try await writer.write(contentsOf: messages)
                    for await _ in keepOpen { break }
                }

                return try await serviceClient.batchAppend(request: request, options: callOptions) { response in
                    var byCorrelation: [UUID: Response.ItemResult] = [:]

                    for try await message in response.messages {
                        guard let correlationId = message.correlationID.toUUID() else { continue }
                        let event = eventByCorrelation[correlationId]
                        let stream = (try? message.streamIdentifier.toIdentifier())
                            ?? event?.streamIdentifier
                            ?? .init(name: "")

                        switch message.result {
                        case let .success(success):
                            let revision: UInt64? = {
                                if case let .currentRevision(value)? = success.currentRevisionOption { return value }
                                return nil
                            }()
                            let position: StreamPosition? = {
                                if case let .position(pos)? = success.positionOption {
                                    return .at(commitPosition: pos.commitPosition, preparePosition: pos.preparePosition)
                                }
                                return nil
                            }()
                            byCorrelation[correlationId] = .success(.init(
                                streamIdentifier: stream,
                                currentRevision: revision,
                                position: position
                            ))
                        case let .error(status):
                            byCorrelation[correlationId] = .failure(.init(
                                streamIdentifier: stream,
                                message: status.message,
                                expectedRevision: event?.expectedRevision ?? .any
                            ))
                        case .none:
                            continue
                        }

                        if byCorrelation.count == streamEvents.count {
                            releaseRequest.finish()
                            break
                        }
                    }

                    let ordered = zip(streamEvents, correlationIds).map { streamEvent, correlationId in
                        byCorrelation[correlationId] ?? .failure(.init(
                            streamIdentifier: streamEvent.streamIdentifier,
                            message: "No response received for this item.",
                            expectedRevision: streamEvent.expectedRevision
                        ))
                    }
                    return Response(results: ordered)
                }
            }
        }
    }
}

extension Streams.BatchAppend {
    /// Result of a completed batch append. Because BatchAppend is non-atomic, inspect ``results``
    /// (or ``failed``) to see which items succeeded and which did not.
    public struct Response: Sendable {
        /// Per-item results, in the same order as the input `events`.
        public let results: [ItemResult]

        /// Items that were appended successfully.
        public var succeeded: [ItemResult.Success] {
            results.compactMap { if case let .success(s) = $0 { return s } else { return nil } }
        }

        /// Items that were rejected (e.g. version conflict, access denied).
        public var failed: [ItemResult.Failure] {
            results.compactMap { if case let .failure(f) = $0 { return f } else { return nil } }
        }

        /// `true` when at least one item failed.
        public var hasFailures: Bool { !failed.isEmpty }

        init(results: [ItemResult]) {
            self.results = results
        }

        /// Outcome of a single append within the batch.
        public enum ItemResult: Sendable {
            case success(Success)
            case failure(Failure)

            /// A successfully appended item.
            public struct Success: Sendable {
                /// The stream that received the events.
                public let streamIdentifier: StreamIdentifier
                /// The stream's revision after the append; `nil` when the stream had no events.
                public let currentRevision: UInt64?
                /// Global log position of the append, when reported.
                public let position: StreamPosition?
            }

            /// A rejected item.
            public struct Failure: Sendable {
                /// The stream the item targeted.
                public let streamIdentifier: StreamIdentifier
                /// Server-provided error message.
                public let message: String
                /// The expected revision this item requested (useful when retrying a conflict).
                public let expectedRevision: StreamRevision
            }
        }
    }
}
