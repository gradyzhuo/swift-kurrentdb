//
//  Stream.Read.swift
//
//
//  Created by Grady Zhuo on 2023/10/21.
//

import Foundation
import GRPC
import GRPCEncapsulates

extension StreamClient {
    public struct Read: UnaryStream {
        public typealias Request = GenericGRPCRequest<EventStore_Client_Streams_ReadReq>

        public let streamIdentifier: Stream.Identifier
        public let cursor: Cursor<CursorPointer>
        public let options: Options

        package func build() throws -> Request.UnderlyingMessage {
            try .with {
                $0.options = options.build()
                $0.options.stream.streamIdentifier = try streamIdentifier.build()
                cursor.build(options: &$0.options)
            }
        }
    }

    public struct ReadAll: UnaryStream {
        public typealias Options = StreamClient.Read.Options
        public typealias Request = StreamClient.Read.Request
        public typealias Response = StreamClient.Read.Response

        public let cursor: Cursor<CursorPointer>
        public let options: Options

        package func build() throws -> Request.UnderlyingMessage {
            .with {
                $0.options = options.options
                cursor.build(options: &$0.options)
            }
        }
    }
}

extension StreamClient.ReadAll {
    public struct CursorPointer {
        let position: StreamClient.Read.Position
        let direction: StreamClient.Read.Direction

        public static func forwardOn(commitPosition: UInt64, preparePosition: UInt64) -> Self {
            .init(position: .init(commit: commitPosition, prepare: preparePosition), direction: .forward)
        }

        public static func backwardFrom(commitPosition: UInt64, preparePosition: UInt64) -> Self {
            .init(position: .init(commit: commitPosition, prepare: preparePosition), direction: .backward)
        }
    }
}

extension StreamClient.Read {
    public struct CursorPointer {
        let revision: UInt64
        let direction: StreamClient.Read.Direction

        public static func forwardOn(revision: UInt64) -> Self {
            .init(revision: revision, direction: .forward)
        }

        public static func backwardFrom(revision: UInt64) -> Self {
            .init(revision: revision, direction: .backward)
        }
    }

    public struct Position {
        public let commit: UInt64
        public let prepare: UInt64
    }

    public enum Direction {
        case forward
        case backward
    }

    public enum UUIDOption {
        case structured
        case string
    }

    public enum ControlOption {
        case compatibility(UInt32)
    }
}

extension Cursor where Pointer == StreamClient.Read.CursorPointer {
    var direction: StreamClient.Read.Direction {
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

extension StreamClient.Read.Direction {
    func build(options: inout EventStore_Client_Streams_ReadReq.Options) {
        switch self {
        case .forward:
            options.readDirection = .forwards
        case .backward:
            options.readDirection = .backwards
        }
    }
}

extension Cursor where Pointer == StreamClient.Read.CursorPointer {
    public func build(options: inout EventStore_Client_Streams_ReadReq.Options) {
        switch self {
        case .start:
            options.stream.start = .init()
            options.readDirection = .forwards
        case .end:
            options.stream.end = .init()
            options.readDirection = .backwards
        case let .specified(pointer):
            options.stream.revision = pointer.revision
            pointer.direction.build(options: &options)
        }
    }

    public func build(options: inout EventStore_Client_Streams_ReadReq.Options.StreamOptions) {
        switch self {
        case .start:
            options.start = .init()
        case .end:
            options.end = .init()
        case let .specified(pointer):
            options.revision = pointer.revision
        }
    }
}

extension StreamClient.Read.UUIDOption {
    func build(options: inout EventStore_Client_Streams_ReadReq.Options) {
        switch self {
        case .structured:
            options.uuidOption.structured = .init()
        case .string:
            options.uuidOption.string = .init()
        }
    }
}

extension StreamClient.Read.ControlOption {
    func build(options: inout EventStore_Client_Streams_ReadReq.Options) {
        switch self {
        case let .compatibility(compatibility):
            options.controlOption.compatibility = compatibility
        }
    }
}

extension StreamClient.Read.Position {
    func build() -> EventStore_Client_Streams_ReadReq.Options.Position {
        .with {
            $0.commitPosition = commit
            $0.preparePosition = prepare
        }
    }

    func build(options: inout EventStore_Client_Streams_ReadReq.Options) {
        options.all.position = .with {
            $0.commitPosition = commit
            $0.preparePosition = prepare
        }
    }

    public func cusor(direction: StreamClient.Read.Direction) -> Cursor<StreamClient.ReadAll.CursorPointer> {
        .specified(
            .init(
                position: self,
                direction: direction
            )
        )
    }
}

extension Cursor where Pointer == StreamClient.ReadAll.CursorPointer {
    public func build() -> EventStore_Client_Streams_ReadReq.Options.AllOptions {
        .with {
            switch self {
            case .start:
                $0.start = .init()
            case .end:
                $0.end = .init()
            case let .specified(pointer):
                $0.position = pointer.position.build()
            }
        }
    }

    public func build(options: inout EventStore_Client_Streams_ReadReq.Options) {
        switch self {
        case .start:
            options.all.start = .init()
            options.readDirection = .forwards
        case .end:
            options.all.end = .init()
            options.readDirection = .backwards
        case let .specified(pointer):
            pointer.position.build(options: &options)
            pointer.direction.build(options: &options)
        }
    }
}

extension StreamClient.FilterOption {
    func build(options: inout EventStore_Client_Streams_ReadReq.Options) {
        options.filter = .with {
            switch self.type {
            case let .streamName(regex):
                $0.streamIdentifier = .with {
                    $0.regex = regex
                    $0.prefix = self.prefixes
                }

            case let .eventType(regex):
                $0.eventType = .with {
                    $0.regex = regex
                    $0.prefix = self.prefixes
                }
            }
            switch self.window {
            case .count:
                $0.count = .init()
            case let .max(max):
                $0.max = max
            }
            $0.checkpointIntervalMultiplier = self.checkpointIntervalMultiplier
        }
    }
}

extension Stream.Identifier {
    func build(options: inout StreamClient.Read.Options.UnderlyingMessage) throws {
        options.stream = try .with {
            $0.streamIdentifier = try self.build()
        }
    }
}

extension StreamClient.Read {
    public struct Response: GRPCResponse {
        public enum Content {
            case event(readEvent: ReadEvent)
            case commitPosition(firstStream: UInt64)
            case commitPosition(lastStream: UInt64)
            case position(lastAllStream: Stream.Position)
        }

        public typealias UnderlyingMessage = EventStore_Client_Streams_ReadResp

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
            content = .position(lastAllStream: .init(commit: commitPosition, prepare: preparePosition))
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
