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
        public let cursor: Cursor<StreamRevision>
        public let options: Options

        public init(from streamIdentifier: StreamIdentifier, cursor: Cursor<StreamRevision>, options: Options) {
            self.streamIdentifier = streamIdentifier
            self.cursor = cursor
            self.options = options
        }

        package func requestMessage() throws -> UnderlyingRequest {
            try .with {
                $0.options = options.build()
                $0.options.stream.streamIdentifier = try streamIdentifier.build()
                $0.options.subscription = .init()

                $0.options.readDirection = .forwards
                switch cursor {
                case .start:
                    $0.options.stream.start = .init()
                case .end:
                    $0.options.stream.end = .init()
                case let .specified(revision):
                    $0.options.stream.revision = revision.value
                }
            }
        }

        package func send(client: ServiceClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Responses {
            let (stream, continuation) = AsyncThrowingStream.makeStream(of: UnderlyingResponse.self)
            Task {
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

extension Streams.Subscription{
    package convenience init(messages: AsyncThrowingStream<Streams.Subscribe.UnderlyingResponse , any Error>) async throws {
        var iterator = messages.makeAsyncIterator()

        let subscriptionId: String? = if case let .confirmation(confirmation) = try await iterator.next()?.content {
            confirmation.subscriptionID
        } else {
            nil
        }

        let (stream, continuation) = AsyncThrowingStream.makeStream(of: ReadEvent.self)
        Task {
            while let message = try await iterator.next() {
                if case let .event(message) = message.content {
                    try continuation.yield(.init(message: message))
                }
            }
        }
        let events = stream
        self.init(events: events, subscriptionId: subscriptionId)
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
                throw ClientError.readResponseError(message: "content not found in response: \(message)")
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
                throw EventStoreError.resourceNotFound(reason: "The name '\(String(describing: streamName))' of streams not found.")
            default:
                throw EventStoreError.unsupportedFeature
            }
        }
    }
}

extension Streams.Subscribe {
    public struct Options: EventStoreOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        public private(set) var resolveLinks: Bool
        public private(set) var uuidOption: UUIDOption

        public init(resolveLinks: Bool = false, uuidOption: UUIDOption = .string) {
            self.resolveLinks = resolveLinks
            self.uuidOption = uuidOption
        }

        package func build() -> UnderlyingMessage {
            .with {
                $0.noFilter = .init()

                switch uuidOption {
                case .structured:
                    $0.uuidOption.structured = .init()
                case .string:
                    $0.uuidOption.string = .init()
                }

                $0.resolveLinks = resolveLinks
            }
        }

        @discardableResult
        public func set(resolveLinks: Bool) -> Self {
            withCopy { options in
                options.resolveLinks = resolveLinks
            }
        }

        @discardableResult
        public func set(uuidOption: UUIDOption) -> Self {
            withCopy { options in
                options.uuidOption = uuidOption
            }
        }
    }
}
