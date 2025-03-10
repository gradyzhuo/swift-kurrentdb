//
//  ReadResponse.swift
//  kurrentdb-swift
//
//  Created by Grady Zhuo on 2025/3/10.
//

import GRPCEncapsulates

extension Streams {
    public struct ReadResponse: GRPCResponse {
        public enum Content: Sendable {
            case unserviceable(link: RecordedEvent?)
            case event(readEvent: ReadEvent)
            case readEvent(recorded: RecordedEvent, link: RecordedEvent?, commit: StreamPosition?)
            case commitPosition(firstStream: UInt64)
            case commitPosition(lastStream: UInt64)
            case position(lastAllStream: StreamPosition)
        }

        package typealias UnderlyingMessage = UnderlyingClient.UnderlyingService.Method.Read.Output

        public var content: Content

        init(content: Content) {
            self.content = content
        }

        package init(from message: UnderlyingMessage) throws {
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
                do{
                    try self.init(message: value)
                }catch let error as ClientError{
                    if value.hasLink {
                        try self.init(content: .unserviceable(link: RecordedEvent(message: value.link)))
                    }else{
                        self.init(content: .unserviceable(link: nil))
                    }
                }
                
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
