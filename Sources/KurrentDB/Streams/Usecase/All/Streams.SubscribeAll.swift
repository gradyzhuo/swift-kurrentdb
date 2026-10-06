//
//  Streams.SubscribeAll.swift
//  KurrentStreams
//
//  Created by Grady Zhuo on 2023/10/21.
//

import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix

extension Streams where Target == AllStreamsTarget {
    /// Usecase that opens a live subscription to the global `$all` stream.
    public struct SubscribeAll: UnaryStream {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = ReadAll.UnderlyingRequest
        package typealias UnderlyingResponse = ReadAll.UnderlyingResponse
        public typealias Responses = Subscription

        package var methodDescriptor: GRPCCore.MethodDescriptor {
            ServiceClient.UnderlyingService.Method.Read.descriptor
        }

        package static var name: String {
            "Streams.\(Self.self)"
        }

        /// Options controlling the subscription start position and filter.
        public let options: Options

        init(options: Options) {
            self.options = options
        }

        /// Builds the underlying gRPC request message for subscribing to all streams using the configured options.
        ///
        /// - Returns: The constructed gRPC request message.
        /// - Throws: An error if encoding the options fails.
        package func requestMessage() throws -> UnderlyingRequest {
            .with {
                $0.options = options.build()
            }
        }

        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions, completion: @Sendable @escaping ((any Error)?) -> Void) async throws -> Responses {
            let messages = ResponseHandoff<UnderlyingResponse>(onTermination: completion)

            let handlerCancellation = HandlerCancellation()
            Task {
                do {
                    let client = ServiceClient(wrapping: connection)
                    try await client.read(request: request, options: callOptions) {
                        // An infinite loop must be executed inside the `onResponse` closure; if you leave the onResponse closure, the connection will end.
                        do {
                            for try await message in $0.messages.cancelOnGracefulShutdown() {
                                try await messages.send(message)
                            }
                        } catch is CancellationError {
                            handlerCancellation.mark()
                            throw CancellationError()
                        }
                        // Graceful shutdown does not cancel this task, a deadline does.
                        if Task.isCancelled { handlerCancellation.mark() }
                    }
                    // Older grpc-swift returns normally when the deadline cancelled the handler.
                    if handlerCancellation.isMarked { throw deadlineExceededError() }
                    // After the RPC returned: a deadline cancels the handler and ends the loop above
                    // quietly (the merge behind cancelOnGracefulShutdown yields nil on cancellation),
                    // so finishing inside the handler would commit a clean end before client.read
                    // throws its deadlineExceeded.
                    messages.finish()
                } catch {
                    // Older grpc-swift rethrows the handler's CancellationError instead of the
                    // deadline error. An unrequested CancellationError is raised either by grpc-swift enforcing the call deadline,
                    // or by the consumer cancelling the hand-off; the latter is harmless because the
                    // hand-off is already terminal, so finish(throwing:) is a no-op.
                    messages.finish(throwing: deadlineOrOriginal(error))
                }
            }
            return try await .init(messages: messages)
        }
    }
}

extension Streams.SubscribeAll where Target == AllStreamsTarget {
    /// A single message received from a `$all` stream subscription.
    public struct Response: GRPCResponse {
        /// Payload variants delivered by the `$all` subscription.
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

        package init(from message: UnderlyingResponse) throws(KurrentError) {
            guard let content = message.content else {
                throw .initializationError(reason: "content not found in response: \(message)")
            }
            try self.init(content: content)
        }

        init(subscriptionId: String) throws(KurrentError) {
            content = .confirmation(subscriptionId: subscriptionId)
        }

        init(message: UnderlyingMessage.ReadEvent) throws(KurrentError) {
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

        init(content: UnderlyingMessage.OneOf_Content) throws(KurrentError) {
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

extension Streams.SubscribeAll where Target == AllStreamsTarget {
    /// Options that control `$all` subscription behaviour.
    public struct Options: CommandOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        /// Global log position at which the subscription starts.
        public var position: PositionCursor
        /// When `true`, linked events are resolved to their targets.
        public var resolveLinksEnabled: Bool
        /// UUID representation used in event metadata.
        public var uuidOption: UUIDOption
        /// Optional filter applied server-side to reduce event noise.
        public var filter: StreamFilter?

        /// Initialises options with sensible defaults (start from end, string UUIDs, no filter, no link resolution).
        public init() {
            resolveLinksEnabled = false
            uuidOption = .string
            filter = nil
            position = .end
        }

        /// Builds the underlying gRPC request message for subscribing to all streams using the configured options.
        ///
        /// Encodes filter, UUID option, starting position, link resolution, and other subscription parameters into the request message.
        ///
        /// - Returns: The constructed gRPC request message reflecting the current subscription options.
        package func build() -> UnderlyingMessage {
            .with {
                if let filter {
                    $0.filter = filter.buildFilterOptions()
                } else {
                    $0.noFilter = .init()
                }

                switch uuidOption {
                case .structured:
                    $0.uuidOption.structured = .init()
                case .string:
                    $0.uuidOption.string = .init()
                }

                switch position {
                case .start:
                    $0.all.start = .init()
                case .end:
                    $0.all.end = .init()
                case let .specified(commitPosition, preparePosition):
                    $0.all.position = .with {
                        $0.commitPosition = commitPosition
                        $0.preparePosition = preparePosition
                    }
                }

                $0.resolveLinks = resolveLinksEnabled
                $0.readDirection = .forwards
                $0.subscription = .init()
                $0.readDirection = .forwards
            }
        }
    }
}

extension Streams.Subscription where Target == AllStreamsTarget {
    package init(messages: ResponseHandoff<Streams.SubscribeAll.UnderlyingResponse>) async throws {
        let first: Streams.SubscribeAll.UnderlyingResponse?
        do {
            first = try await messages.next()
        } catch {
            messages.cancel()
            throw error
        }
        guard case let .confirmation(confirmation) = first?.content else {
            messages.cancel()
            throw KurrentError.subscriptionTerminated(subscriptionId: nil)
        }

        let events = messages.makeStream { message -> ReadEvent? in
            switch message.content {
            case let .event(value):
                return try ReadEvent(message: value)
            case .caughtUp:
                logger.debug("[Streams.SubscribeAll] Subscription caught up with the $all stream.")
                return nil
            case let content?:
                logger.debug("[Streams.SubscribeAll] Received non-event subscription message: \(content)")
                return nil
            case nil:
                return nil
            }
        }
        self.init(events: events, subscriptionId: confirmation.subscriptionID, messages: messages)
    }
}
