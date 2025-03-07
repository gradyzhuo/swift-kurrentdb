//
//  Streams.ReadAll.swift
//  KurrentStreams
//
//  Created by 卓俊諺 on 2025/1/3.
//

import GRPCCore
import GRPCEncapsulates

extension Streams where Target == AllStreams {
    public struct ReadAll: UnaryStream {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.Read.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.Read.Output
        public typealias Responses = AsyncThrowingStream<Response, Error>

        public let cursor: Cursor<CursorPointer>
        public let options: Options

        init(cursor: Cursor<CursorPointer>, options: Options) {
            self.cursor = cursor
            self.options = options
        }

        package func requestMessage() throws -> UnderlyingRequest {
            .with {
                $0.options = options.build()

                switch cursor {
                case .start:
                    $0.options.all.start = .init()
                    $0.options.readDirection = .forwards
                case .end:
                    $0.options.all.end = .init()
                    $0.options.readDirection = .backwards
                case let .specified(pointer):
                    $0.options.all.position = .with {
                        $0.commitPosition = pointer.position.commit
                        $0.preparePosition = pointer.position.prepare
                    }

                    if case .forward = pointer.direction {
                        $0.options.readDirection = .forwards
                    } else {
                        $0.options.readDirection = .backwards
                    }
                }
            }
        }

        package func send(client: ServiceClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Responses {
            try await withThrowingTaskGroup(of: Void.self) { _ in
                let (stream, continuation) = AsyncThrowingStream.makeStream(of: Response.self)
                try await client.read(request: request, options: callOptions) {
                    for try await message in $0.messages {
                        try continuation.yield(handle(message: message))
                    }
                }
                return stream
            }
        }
    }
}

extension Streams.ReadAll where Target == AllStreams {
    public struct CursorPointer: Sendable {
        let position: StreamPosition
        let direction: Direction

        public static func forwardOn(commitPosition: UInt64, preparePosition: UInt64) -> Self {
            .init(position: .at(commitPosition: commitPosition, preparePosition: preparePosition), direction: .forward)
        }

        public static func backwardFrom(commitPosition: UInt64, preparePosition: UInt64) -> Self {
            .init(position: .at(commitPosition: commitPosition, preparePosition: preparePosition), direction: .backward)
        }
    }
}

extension Streams.ReadAll where Target == AllStreams {
    public struct Response: GRPCResponse {
        public enum Content: Sendable {
            case event(readEvent: ReadEvent)
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

extension Streams.ReadAll{
    public struct Options: EventStoreOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        public private(set) var resolveLinks: Bool
        public private(set) var limit: UInt64
        public private(set) var uuidOption: UUIDOption
        public private(set) var compatibility: UInt32

        public init(resolveLinks: Bool = false, limit: UInt64 = .max, uuidOption: UUIDOption = .string, compatibility: UInt32 = 0) {
            self.resolveLinks = resolveLinks
            self.limit = limit
            self.uuidOption = uuidOption
            self.compatibility = compatibility
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

                $0.controlOption = .with {
                    $0.compatibility = compatibility
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
        public func set(uuidOption: UUIDOption) -> Self {
            withCopy { options in
                options.uuidOption = uuidOption
            }
        }

        @discardableResult
        public func set(compatibility: UInt32) -> Self {
            withCopy { options in
                options.compatibility = compatibility
            }
        }
    }
}
