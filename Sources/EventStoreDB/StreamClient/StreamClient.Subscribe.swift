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
    public struct Subscribe: UnaryStream {
        public typealias Request = GenericGRPCRequest<EventStore_Client_Streams_ReadReq>

        public let streamIdentifier: Stream.Identifier
        public let cursor: Cursor<Stream.Revision>
        public let options: Options

        package func build() throws -> Request.UnderlyingMessage {
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
                    $0.options.stream.revision = revision
                }
            }
        }
    }

}

extension StreamClient.Subscribe {
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


extension StreamClient.Subscribe {
    public struct Options: EventStoreOptions {
        public typealias UnderlyingMessage = EventStore_Client_Streams_ReadReq.Options

        public private(set) var resolveLinks: Bool = false
        public private(set) var uuidOption: Stream.UUIDOption = .string

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
