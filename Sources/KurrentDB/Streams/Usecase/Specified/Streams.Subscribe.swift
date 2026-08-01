//
//  Streams.Subscribe.swift
//  KurrentStreams
//
//  Created by Grady Zhuo on 2023/10/21.
//

import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix

extension Streams where Target: SpecifiedStreamTarget {
    /// Usecase that opens a live subscription to a single named stream.
    public struct Subscribe: UnaryStream {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = Read.UnderlyingRequest
        package typealias UnderlyingResponse = Read.UnderlyingResponse
        public typealias Responses = Subscription

        package var methodDescriptor: GRPCCore.MethodDescriptor {
            ServiceClient.UnderlyingService.Method.Read.descriptor
        }

        package static var name: String {
            "Streams.\(Self.self)"
        }

        /// Identifier of the stream to subscribe to.
        public let streamIdentifier: StreamIdentifier
        /// Options controlling the subscription behaviour.
        public let options: Options

        /// Creates a subscribe usecase for the given stream and options.
        public init(from streamIdentifier: StreamIdentifier, options: Options) {
            self.streamIdentifier = streamIdentifier
            self.options = options
        }

        /// Constructs the underlying gRPC request message for subscribing to a stream.
        ///
        /// - Returns: A configured `UnderlyingRequest` with subscription options and stream identifier set.
        /// - Throws: An error if building the stream identifier fails.
        package func requestMessage() throws -> UnderlyingRequest {
            try .with {
                $0.options = options.build()
                $0.options.stream.streamIdentifier = try streamIdentifier.build()
            }
        }

        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions, completion: @Sendable @escaping ((any Error)?) -> Void) async throws -> Responses {
            let responses = AsyncThrowingStream.makeStream(of: UnderlyingResponse.self)
            responses.continuation.onTermination = { termination in
                if case let .finished(error) = termination {
                    completion(error)
                } else {
                    completion(nil)
                }
            }

            Task {
                do {
                    let client = ServiceClient(wrapping: connection)
                    try await client.read(request: request, options: callOptions) {
                        // An infinite loop must be executed inside the `onResponse` closure; if you leave the onResponse closure, the connection will end.
                        for try await message in $0.messages.cancelOnGracefulShutdown() {
                            responses.continuation.yield(message)
                        }
                        responses.continuation.finish()
                    }
                } catch {
                    responses.continuation.finish(throwing: error)
                }
            }
            return try await .init(messages: responses)
        }
    }
}

extension Streams.Subscribe {
    /// A single message received from a stream subscription.
    public struct Response: GRPCResponse {
        /// Payload variants delivered by the subscription.
        public enum Content: Sendable {
            /// A resolved event read from the stream.
            case event(readEvent: ReadEvent)
            /// Server confirmation carrying the assigned subscription ID.
            case confirmation(subscriptionId: String)
            /// First commit position seen on the stream.
            case commitPosition(firstStream: UInt64)
            /// Last commit position seen on the stream.
            case commitPosition(lastStream: UInt64)
            /// Last position across all streams.
            case position(lastAllStream: StreamPosition)
        }

        package typealias UnderlyingMessage = UnderlyingResponse

        /// The content delivered in this response message.
        public var content: Content

        init(content: Content) {
            self.content = content
        }

        package init(from message: UnderlyingResponse) throws {
            guard let content = message.content else {
                throw KurrentError.internalParsingError(reason: "content not found in response: \(message)")
            }
            try self.init(content: content)
        }

        init(subscriptionId: String) throws {
            content = .confirmation(subscriptionId: subscriptionId)
        }

        init(message: UnderlyingMessage.ReadEvent) throws {
            content = try .event(readEvent: .init(message: message))
        }

        init(firstStreamPosition commitPosition: UInt64) {
            content = .commitPosition(firstStream: commitPosition)
        }

        init(lastStreamPosition commitPosition: UInt64) {
            content = .commitPosition(lastStream: commitPosition)
        }

        init(lastAllStreamPosition commitPosition: UInt64, preparePosition: UInt64) {
            content = .position(lastAllStream: .at(commitPosition: commitPosition, preparePosition: preparePosition))
        }

        init(content: UnderlyingMessage.OneOf_Content) throws {
            switch content {
            case let .confirmation(confirmation):
                try self.init(subscriptionId: confirmation.subscriptionID)
            case let .event(value):
                try self.init(message: value)
            case let .firstStreamPosition(value):
                self.init(firstStreamPosition: value)
            case let .lastStreamPosition(value):
                self.init(lastStreamPosition: value)
            case let .lastAllStreamPosition(value):
                self.init(lastAllStreamPosition: value.commitPosition, preparePosition: value.preparePosition)
            case let .streamNotFound(errorMessage):
                let streamName = String(data: errorMessage.streamIdentifier.streamName, encoding: .utf8) ?? ""
                throw KurrentError.resourceNotFound(reason: "The name '\(String(describing: streamName))' of streams not found.")
            default:
                throw KurrentError.internalParsingError(reason: "The content of the ReadEvent, should be either 'confirmation', 'event', 'firstStreamPosition', 'lastStreamPosition', or 'lastAllStreamPosition'.")
            }
        }
    }
}

extension Streams.Subscribe {
    /// Options that control stream subscription behaviour.
    public struct Options: CommandOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        /// When `true`, linked events are resolved to their targets.
        public var resolveLinksEnabled: Bool
        /// UUID representation used in event metadata.
        public var uuidOption: UUIDOption
        /// Stream revision from which the subscription starts.
        public var revision: RevisionCursor

        /// Initialises options with sensible defaults (start from end, string UUIDs, no link resolution).
        public init() {
            resolveLinksEnabled = false
            uuidOption = .string
            revision = .end
        }

        /// Constructs the underlying gRPC options message for a stream subscription.
        ///
        /// Configures the filter, UUID representation, stream revision, link resolution, subscription, and read direction based on the current option settings.
        ///
        /// - Returns: A configured `UnderlyingMessage` representing the subscription options.
        package func build() -> UnderlyingMessage {
            .with {
                $0.noFilter = .init()

                switch uuidOption {
                case .structured:
                    $0.uuidOption.structured = .init()
                case .string:
                    $0.uuidOption.string = .init()
                }

                switch revision {
                case .start:
                    $0.stream.start = .init()
                case .end:
                    $0.stream.end = .init()
                case let .specified(revision):
                    $0.stream.revision = revision
                }

                $0.resolveLinks = resolveLinksEnabled
                $0.subscription = .init()
                $0.readDirection = .forwards
            }
        }
    }
}

extension Streams.Subscription where Target: SpecifiedStreamTarget {
    package init(messages: (stream: AsyncThrowingStream<Streams.Subscribe.UnderlyingResponse, any Error>, continuation: AsyncThrowingStream<Streams.Subscribe.UnderlyingResponse, any Error>.Continuation)) async throws {
        var iterator = messages.stream.makeAsyncIterator()

        guard case let .confirmation(confirmation) = try await iterator.next()?.content else {
            throw KurrentError.subscriptionTerminated(subscriptionId: nil)
        }

        let (events, continuation) = AsyncThrowingStream.makeStream(of: ReadEvent.self)
        continuation.onTermination = { termination in
            if case let .finished(error) = termination {
                messages.continuation.finish(throwing: error)
            } else {
                messages.continuation.finish()
            }
        }

        let innerTask = Task {
            do {
                while let message = try await iterator.next() {
                    switch message.content {
                    case let .event(value):
                        try continuation.yield(.init(message: value))
                    case .caughtUp:
                        logger.debug("[Streams.Subscribe] Subscription caught up with the stream.")
                    case let content?:
                        logger.debug("[Streams.Subscribe] Received non-event subscription message: \(content)")
                    case nil:
                        break
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        self.init(events: events, continuation: continuation, subscriptionId: confirmation.subscriptionID, task: innerTask)
    }
}
