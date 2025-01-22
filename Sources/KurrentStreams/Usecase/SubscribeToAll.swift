//
//  StreamClient.SubscribeToAll.swift
//
//
//  Created by Grady Zhuo on 2023/10/21.
//

import KurrentCore
import GRPCNIOTransportHTTP2Posix
import GRPCCore
import GRPCEncapsulates

public struct SubscribeToAll: UnaryStream {
    public typealias Client = Service
    public typealias UnderlyingRequest = Read.UnderlyingRequest
    public typealias UnderlyingResponse = Read.UnderlyingResponse
    public typealias Responses = Subscription
    
    public let cursor: Cursor<Stream.Position>
    public let options: Options
    
    internal init(cursor: Cursor<Stream.Position>, options: Options) {
        self.cursor = cursor
        self.options = options
    }
    
    package func requestMessage() throws -> UnderlyingRequest {
        return .with {
            $0.options = options.build()
            $0.options.readDirection = .forwards
            $0.options.subscription = .init()

            switch cursor {
            case .start:
                $0.options.all.start = .init()
            case .end:
                $0.options.all.end = .init()
            case let .specified(position):
                $0.options.all.position = .with {
                    $0.commitPosition = position.commit
                    $0.preparePosition = position.prepare
                }
            }
        }
    }

    public func send(client: Client.UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws ->Responses {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: UnderlyingResponse.self)
        Task{
            try await client.read(request: request, options: callOptions) {
                for try await message in $0.messages {
                    continuation.yield(message)
                }
            }
        }
        return try await .init(messages: stream)
    }

}

extension SubscribeToAll {
    public struct Response: GRPCResponse {
        public enum Content: Sendable {
            case event(readEvent: ReadEvent)
            case confirmation(subscriptionId: String)
            case commitPosition(firstStream: UInt64)
            case commitPosition(lastStream: UInt64)
            case position(lastAllStream: Stream.Position)
        }

        public typealias UnderlyingMessage = UnderlyingResponse

        public var content: Content

        init(content: Content) {
            self.content = content
        }

        public init(from message: EventStore_Client_Streams_ReadResp) throws {
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
//    public struct Response: GRPCResponse {
//        public enum Content: Sendable {
//            case event(readEvent: ReadEvent)
//            case commitPosition(firstStream: UInt64)
//            case commitPosition(lastStream: UInt64)
//            case position(lastAllStream: Stream.Position)
//        }
//
//        public typealias UnderlyingMessage = UnderlyingResponse
//
//        public var content: Content
//
//        init(content: Content) {
//            self.content = content
//        }
//
//        public init(from message: EventStore_Client_Streams_ReadResp) throws {
//            guard let content = message.content else {
//                throw ClientError.readResponseError(message: "content not found in response: \(message)")
//            }
//            try self.init(content: content)
//        }
//
//        init(message: UnderlyingMessage.ReadEvent) throws {
//            content = try .event(readEvent: .init(message: message))
//        }
//
//        init(firstStreamPosition commitPosition: UInt64) {
//            content = .commitPosition(firstStream: commitPosition)
//        }
//
//        init(lastStreamPosition commitPosition: UInt64) {
//            content = .commitPosition(lastStream: commitPosition)
//        }
//
//        init(lastAllStreamPosition commitPosition: UInt64, preparePosition: UInt64) {
//            content = .position(lastAllStream: .at(commitPosition: commitPosition, preparePosition: preparePosition))
//        }
//
//        init(content: UnderlyingMessage.OneOf_Content) throws {
//            switch content {
//            case let .event(value):
//                try self.init(message: value)
//            case let .firstStreamPosition(value):
//                self.init(firstStreamPosition: value)
//            case let .lastStreamPosition(value):
//                self.init(lastStreamPosition: value)
//            case let .lastAllStreamPosition(value):
//                self.init(lastAllStreamPosition: value.commitPosition, preparePosition: value.preparePosition)
//            case let .streamNotFound(errorMessage):
//                let streamName = String(data: errorMessage.streamIdentifier.streamName, encoding: .utf8) ?? ""
//                throw EventStoreError.resourceNotFound(reason: "The name '\(String(describing: streamName))' of streams not found.")
//            default:
//                throw EventStoreError.unsupportedFeature
//            }
//        }
//    }
}

extension SubscribeToAll {
    public struct Options: EventStoreOptions {
        public typealias UnderlyingMessage = UnderlyingRequest.Options

        public private(set) var resolveLinks: Bool
        public private(set) var uuidOption: Stream.UUIDOption
        public private(set) var filter: Stream.SubscriptionFilter?

        public init(resolveLinks: Bool = false, uuidOption: Stream.UUIDOption = .string, filter: Stream.SubscriptionFilter? = nil) {
            self.resolveLinks = resolveLinks
            self.uuidOption = uuidOption
            self.filter = filter
        }
        
        package func build() -> UnderlyingMessage {
            .with {
                if let filter {
                    $0.filter = .with {
                        // filter
                        switch filter.type {
                        case let .streamName(regex):
                            $0.streamIdentifier = .with {
                                $0.regex = regex
                                $0.prefix = filter.prefixes
                            }
                        case let .eventType(regex):
                            $0.eventType = .with {
                                $0.regex = regex
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
        public func set(filter: Stream.SubscriptionFilter) -> Self {
            withCopy { options in
                options.filter = filter
            }
        }

        @discardableResult
        public func set(uuidOption: Stream.UUIDOption) -> Self {
            withCopy { options in
                options.uuidOption = uuidOption
            }
        }
    }
}
