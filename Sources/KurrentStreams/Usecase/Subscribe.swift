//
//  StreamClient.Subscribe.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2023/10/21.
//

import KurrentCore
import GRPCCore
import GRPCNIOTransportHTTP2Posix
import GRPCEncapsulates

public struct Subscribe: UnaryStream {
    public typealias Transport = HTTP2ClientTransport.Posix
    public typealias Client = Service
    public typealias UnderlyingRequest = Read.UnderlyingRequest
    public typealias UnderlyingResponse = Read.UnderlyingResponse
    public typealias Responses = Subscription

    public let streamIdentifier: Stream.Identifier
    public let cursor: Cursor<Stream.Revision>
    public let options: Options
    
    public init(streamIdentifier: Stream.Identifier, cursor: Cursor<Stream.Revision>, options: Options) {
        self.streamIdentifier = streamIdentifier
        self.cursor = cursor
        self.options = options
    }
    
    package func requestMessage() throws -> UnderlyingRequest {
        return try .with {
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
                $0.options.stream.revision = revision
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
extension Subscribe {
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
}

extension Subscribe {
    public struct Options: EventStoreOptions {
        public typealias UnderlyingMessage = UnderlyingRequest.Options

        public private(set) var resolveLinks: Bool
        public private(set) var uuidOption: Stream.UUIDOption

        public init(resolveLinks: Bool = false, uuidOption: Stream.UUIDOption = .string) {
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
        public func set(uuidOption: Stream.UUIDOption) -> Self {
            withCopy { options in
                options.uuidOption = uuidOption
            }
        }
    }
}
