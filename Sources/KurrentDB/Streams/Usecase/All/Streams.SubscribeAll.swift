//
//  Streams.SubscribeToAll.swift
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

        public let cursor: ReadAll.Cursor
        public let options: Options

        init(cursor: ReadAll.Cursor, options: Options) {
            self.cursor = cursor
            self.options = options
        }

        package func requestMessage() throws -> UnderlyingRequest {
            .with {
                $0.options = options.build()
                $0.options.readDirection = .forwards
                $0.options.subscription = .init()
                
                $0.options.readDirection = .forwards
                switch cursor {
                case .start:
                    $0.options.all.start = .init()
                case .end:
                    $0.options.all.end = .init()
                case let .position(commitPosition, preparePosition):
                    $0.options.all.position = .with {
                        $0.commitPosition = commitPosition
                        $0.preparePosition = preparePosition
                    }
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

        public private(set) var resolveLinksEnabled: Bool
        public private(set) var uuidOption: UUIDOption
        public private(set) var filter: SubscriptionFilter?

        public init() {
            self.resolveLinksEnabled = false
            self.uuidOption = .string
            self.filter = nil
        }

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

                $0.resolveLinks = resolveLinksEnabled
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

        @discardableResult
        public func uuidOption(_ uuidOption: UUIDOption) -> Self {
            withCopy { options in
                options.uuidOption = uuidOption
            }
        }
    }
}

//MARK: - Deprecated
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
