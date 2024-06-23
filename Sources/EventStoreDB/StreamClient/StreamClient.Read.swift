//
//  StreamClient.Read.swift
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
    }

    public struct ReadAll: UnaryStream {
        public typealias Options = StreamClient.Read.Options
        public typealias Request = StreamClient.Read.Request
        public typealias Response = StreamClient.Read.Response

        public let cursor: Cursor<CursorPointer>
        public let options: Options

        package func build() throws -> Request.UnderlyingMessage {
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
    }
}

extension StreamClient.ReadAll {
    public struct CursorPointer: Sendable {
        let position: Stream.Position
        let direction: Stream.Direction

        public static func forwardOn(commitPosition: UInt64, preparePosition: UInt64) -> Self {
            .init(position: .at(commitPosition: commitPosition, preparePosition: preparePosition), direction: .forward)
        }

        public static func backwardFrom(commitPosition: UInt64, preparePosition: UInt64) -> Self {
            .init(position: .at(commitPosition: commitPosition, preparePosition: preparePosition), direction: .backward)
        }
    }
}

extension StreamClient.Read {
    public struct CursorPointer: Sendable {
        let revision: UInt64
        let direction: Stream.Direction

        public static func forwardOn(revision: UInt64) -> Self {
            .init(revision: revision, direction: .forward)
        }

        public static func backwardFrom(revision: UInt64) -> Self {
            .init(revision: revision, direction: .backward)
        }
    }
}

extension Cursor where Pointer == StreamClient.Read.CursorPointer {
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

extension Stream.Position {
    public func cusor(direction: Stream.Direction) -> Cursor<StreamClient.ReadAll.CursorPointer> {
        .specified(
            .init(
                position: self,
                direction: direction
            )
        )
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
        public enum Content: Sendable {
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
