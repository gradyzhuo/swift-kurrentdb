//
//  Streams.ReadResponse.swift
//  kurrentdb-swift
//
//  Created by Grady Zhuo on 2025/3/10.
//

import GRPCEncapsulates

extension Streams {
    /// Response returned by a stream read operation.
    public enum ReadResponse: Sendable, GRPCResponse {
        package typealias UnderlyingMessage = UnderlyingClient.UnderlyingService.Method.Read.Output

        /// An event whose original record could not be resolved, optionally carrying its link event.
        case unserviceable(link: RecordedEvent?)
        /// A successfully resolved event.
        case event(readEvent: ReadEvent)

        // TODO: Not sure how to request to get first_stream_position, last_stream_position, first_all_stream_position.
//            case firstStreamPosition(UInt64)
//            case lastStreamPosition(UInt64)
//            case lastAllStreamPosition(commit: UInt64, prepare: UInt64)

        package init(from message: Streams<Target>.UnderlyingClient.UnderlyingService.Method.Read.Output) throws {
            switch message.content {
            case let .event(message):
                do {
                    let readEvent = try ReadEvent(message: message)
                    self = .event(readEvent: readEvent)
                } catch {
                    if message.hasLink {
                        self = try .unserviceable(link: RecordedEvent(message: message.link))
                    } else {
                        self = .unserviceable(link: nil)
                    }
                }
            case let .streamNotFound(errorMessage):
                let streamName = String(data: errorMessage.streamIdentifier.streamName, encoding: .utf8) ?? ""
                throw KurrentError.resourceNotFound(reason: "The name '\(String(describing: streamName))' of streams not found.")
            default:
                throw KurrentError.internalParsingError(reason: "The content of the ReadEvent, should be .event or .streamNotFound.")
            }
        }
    }
}

extension Streams.ReadResponse {
    /// Extracts the resolved ``ReadEvent`` from this response.
    ///
    /// - Returns: The ``ReadEvent`` when the response is `.event`.
    /// - Throws: `KurrentError.unservicableEventLink` if the event link cannot be resolved,
    ///   or `KurrentError.resourceNotFound` if no event is present.
    public var event: ReadEvent {
        get throws(KurrentError) {
            return switch self {
            case let .event(readEvent):
                readEvent
            case let .unserviceable(link):
                if let link {
                    throw .unservicableEventLink(link: link)
                }
                throw .resourceNotFound(reason: "read event not found.")
            }
        }
    }
}
