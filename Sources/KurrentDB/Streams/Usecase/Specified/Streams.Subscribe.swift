//
//  Streams.Subscribe.swift
//  KurrentStreams
//
//  Created by Grady Zhuo on 2023/10/21.
//

import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix

extension Streams {
    public struct Subscribe: UnaryStream {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = Read.UnderlyingRequest
        package typealias UnderlyingResponse = Read.UnderlyingResponse
        public typealias Responses = Subscription

        public let streamIdentifier: StreamIdentifier
        public let options: Options

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
            let (stream, continuation) = AsyncThrowingStream.makeStream(of: UnderlyingResponse.self)
            continuation.onTermination = { termination in
                if case let .finished(error) = termination {
                    completion(error)
                } else {
                    completion(nil)
                }
            }

            Task {
                let client = ServiceClient(wrapping: connection)
                try await client.read(request: request, options: callOptions) {
                    do {
                        for try await message in $0.messages {
                            continuation.yield(message)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
            return try await .init(messages: stream)
        }
    }
}

extension Streams.Subscribe {
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
                throw KurrentError.unsupportedFeature
            }
        }
    }
}

extension Streams.Subscribe {
    public struct Options: EventStoreOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        package private(set) var resolveLinksEnabled: Bool
        package private(set) var uuidOption: UUIDOption
        package private(set) var revision: RevisionCursor

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

        @discardableResult
        public func resolveLinks() -> Self {
            withCopy { options in
                options.resolveLinksEnabled = true
            }
        }

        /// Returns a copy of the options with the specified UUID option set.
        ///
        /// - Parameter uuidOption: The UUID representation to use for events.
        /// - Returns: A new `Options` instance with the updated UUID option.
        @discardableResult
        public func uuidOption(_ uuidOption: UUIDOption) -> Self {
            withCopy { options in
                options.uuidOption = uuidOption
            }
        }

        /// Returns a copy of the options with the revision cursor set to the specified value.
        ///
        /// - Parameter cursor: The revision cursor to use for the subscription.
        /// Returns a copy of the options with the starting revision set to the specified value.
        ///
        /// - Parameter revision: The revision cursor indicating where the subscription should start from.
        /// - Returns: A new `Options` instance with the updated starting revision.
        @discardableResult
        public func startFrom(revision: RevisionCursor) -> Self {
            withCopy { options in
                options.revision = revision
            }
        }
    }
}

// MARK: - Deprecated

extension Streams.Subscribe.Options {
    @available(*, deprecated, renamed: "limit")

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
}
