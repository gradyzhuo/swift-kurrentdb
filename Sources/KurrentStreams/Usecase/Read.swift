//
//  StreamClient.Read.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2023/10/21.
//

import KurrentCore
import GRPCCore
import GRPCEncapsulates

public struct ReadCursorPointer: Sendable {
    public let revision: UInt64
    public let direction: Stream.Direction

    package init(revision: UInt64, direction: Stream.Direction) {
        self.revision = revision
        self.direction = direction
    }

    public static func forwardOn(revision: UInt64) -> Self {
        .init(revision: revision, direction: .forward)
    }

    public static func backwardFrom(revision: UInt64) -> Self {
        .init(revision: revision, direction: .backward)
    }
}

public struct Read: UnaryStream {
    public typealias Client = Service
    public typealias UnderlyingRequest = UnderlyingService.Method.Read.Input
    public typealias UnderlyingResponse = UnderlyingService.Method.Read.Output
    public typealias Responses = AsyncThrowingStream<Response, Error>

    public let streamIdentifier: Stream.Identifier
    public let cursor: Cursor<ReadCursorPointer>
    public let options: Options
    
    internal init(streamIdentifier: Stream.Identifier, cursor: Cursor<ReadCursorPointer>, options: Options) {
        self.streamIdentifier = streamIdentifier
        self.cursor = cursor
        self.options = options
    }
    
    package func requestMessage() throws -> UnderlyingRequest {
        return try .with {
            $0.options = options.build()
            $0.options.stream.streamIdentifier = try streamIdentifier.build()

            switch cursor {
            case .start:
                $0.options.stream.start = .init()
                $0.options.readDirection = .forwards
            case .end:
                $0.options.stream.end = .init()
                $0.options.readDirection = .backwards
            case let .specified(pointer):
                $0.options.stream.revision = pointer.revision

                if case .forward = pointer.direction {
                    $0.options.readDirection = .forwards
                } else {
                    $0.options.readDirection = .backwards
                }
            }
        }
    }
    
    public func send(client: Client.UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Responses {
        return try await withThrowingDiscardingTaskGroup { group in
            let (stream, continuation) = AsyncThrowingStream.makeStream(of: Response.self)
            try await client.read(request: request, options: callOptions) {
                for try await message in $0.messages {
                    try continuation.yield(handle(message: message))
                }
            }
            continuation.finish()
            return stream
        }
    }
}

extension Cursor where Pointer == ReadCursorPointer {
    var direction: Stream.Direction {
        switch self {
        case .start:
            .forward
        case .end:
            .backward
        case let .specified(pointer):
            pointer.direction
        }
    }
}

extension Read {
    public struct Response: GRPCResponse {
        public enum Content: Sendable {
            case event(readEvent: ReadEvent)
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

extension Read {
    public struct Options: EventStoreOptions {
        public typealias UnderlyingMessage = UnderlyingRequest.Options

        public private(set) var resolveLinks: Bool
        public private(set) var limit: UInt64
        public private(set) var uuidOption: Stream.UUIDOption

        package init(resolveLinks: Bool = false, limit: UInt64 = .max, uuidOption: Stream.UUIDOption = .string) {
            self.resolveLinks = resolveLinks
            self.limit = limit
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
                $0.count = limit
            }
        }

        @discardableResult
        public func set(resolveLinks: Bool) -> Self {
            withCopy { options in
                options.resolveLinks = resolveLinks
            }
        }

        @discardableResult
        public func set(limit: UInt64) -> Self {
            withCopy { options in
                options.limit = limit
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
