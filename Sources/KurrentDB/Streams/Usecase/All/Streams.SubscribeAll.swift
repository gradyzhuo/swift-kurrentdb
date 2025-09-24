//
//  Streams.SubscribeAll.swift
//  KurrentStreams
//
//  Created by Grady Zhuo on 2023/10/21.
//

import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix

extension Streams where Target == AllStreams {
    public struct SubscribeAll: UnaryStream {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = ReadAll.UnderlyingRequest
        package typealias UnderlyingResponse = ReadAll.UnderlyingResponse
        public typealias Responses = Subscription

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

        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions, finished: @Sendable @escaping ()->Void) async throws -> Responses {
            let (stream, continuation) = AsyncThrowingStream.makeStream(of: UnderlyingResponse.self)
            continuation.onTermination = { _ in
                finished()
            }
            Task {
                let client = ServiceClient(wrapping: connection)
                try await client.read(request: request, options: callOptions) {
                    for try await message in $0.messages {
                        continuation.yield(message)
                    }
                }
            }
            return try await .init(messages: stream)
        }
    }
}

extension Streams.SubscribeAll where Target == AllStreams {
    public struct Response: GRPCResponse {
        public enum Content: Sendable {
            case event(readEvent: ReadEvent)
            case confirmation(subscriptionId: String)
            case commitPosition(firstStream: UInt64)
            case commitPosition(lastStream: UInt64)
            case position(lastAllStream: StreamPosition)
        }

        package typealias UnderlyingMessage = UnderlyingResponse

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
                throw KurrentError.unsupportedFeature
            }
        }
    }
}

extension Streams.SubscribeAll where Target == AllStreams {
    public struct Options: EventStoreOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        public private(set) var position: PositionCursor
        public private(set) var resolveLinksEnabled: Bool
        public private(set) var uuidOption: UUIDOption
        public private(set) var filter: SubscriptionFilter?

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
                    $0.filter = .with {
                        // filter
                        switch filter.type {
                        case .streamName:
                            $0.streamIdentifier = .with {
                                if let regex = filter.regex {
                                    $0.regex = regex
                                }
                                $0.prefix = filter.prefixes
                            }
                        case .eventType:
                            $0.eventType = .with {
                                if let regex = filter.regex {
                                    $0.regex = regex
                                }
                                $0.prefix = filter.prefixes
                            }
                        }
                        // window
                        switch filter.window {
                        case .count:
                            $0.count = .init()
                        case let .max(value):
                            $0.max = value
                        }

                        // checkpointIntervalMultiplier
                        $0.checkpointIntervalMultiplier = filter.checkpointIntervalMultiplier
                    }
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

        @discardableResult
        public func resolveLinks() -> Self {
            withCopy { options in
                options.resolveLinksEnabled = true
            }
        }

        @discardableResult
        public func filter(_ filter: SubscriptionFilter) -> Self {
            withCopy { options in
                options.filter = filter
            }
        }

        /// Returns a copy of the options with the specified UUID representation option set.
        ///
        /// - Parameter uuidOption: The UUID representation to use for events in the subscription.
        /// - Returns: A copy of the options with the updated UUID option.
        @discardableResult
        public func uuidOption(_ uuidOption: UUIDOption) -> Self {
            withCopy { options in
                options.uuidOption = uuidOption
            }
        }

        /// Returns a copy of the options with the starting position set to the specified cursor.
        ///
        /// - Parameter cursor: The position cursor to use as the starting point for the subscription.
        /// Returns a copy of the options with the starting position set to the specified cursor.
        ///
        /// - Parameter position: The position cursor from which to start the subscription.
        /// - Returns: A copy of the options with the updated starting position.
        @discardableResult
        public func startFrom(position: PositionCursor) -> Self {
            withCopy { options in
                options.position = position
            }
        }
    }
}

// MARK: - Deprecated

extension Streams.SubscribeAll.Options {
    @available(*, deprecated, renamed: "resolveLinks")
    @discardableResult
    public func set(resolveLinks: Bool) -> Self {
        withCopy { options in
            options.resolveLinksEnabled = resolveLinks
        }
    }

    @available(*, deprecated, renamed: "uuidOption")
    @discardableResult
    public func set(uuidOption: UUIDOption) -> Self {
        withCopy { options in
            options.uuidOption = uuidOption
        }
    }

    @available(*, deprecated, renamed: "filter")
    @discardableResult
    public func set(filter: SubscriptionFilter) -> Self {
        withCopy { options in
            options.filter = filter
        }
    }
}
