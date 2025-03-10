//
//  ReadResponse.swift
//  kurrentdb-swift
//
//  Created by Grady Zhuo on 2025/3/10.
//

import GRPCEncapsulates

extension Streams {
    public enum ReadResponse: Sendable, GRPCResponse {
        package typealias UnderlyingMessage = UnderlyingClient.UnderlyingService.Method.Read.Output
        
        case unserviceable(link: RecordedEvent?)
        case event(readEvent: ReadEvent)
        case readEvent(recorded: RecordedEvent, link: RecordedEvent?, commit: StreamPosition?)
        
// TODO: Not sure how to request to get first_stream_position, last_stream_position, first_all_stream_position.
//            case firstStreamPosition(UInt64)
//            case lastStreamPosition(UInt64)
//            case lastAllStreamPosition(commit: UInt64, prepare: UInt64)
        
        package init(from message: Streams<Target>.UnderlyingClient.UnderlyingService.Method.Read.Output) throws {
            switch message.content {
            case let .event(value):
                do{
                    self = try .event(readEvent: .init(message: value))
                }catch{
                    if value.hasLink {
                        self = try .unserviceable(link: RecordedEvent(message: value.link))
                    }else{
                        self = .unserviceable(link: nil)
                    }
                }
            case let .streamNotFound(errorMessage):
                let streamName = String(data: errorMessage.streamIdentifier.streamName, encoding: .utf8) ?? ""
                throw EventStoreError.resourceNotFound(reason: "The name '\(String(describing: streamName))' of streams not found.")
            default:
                throw EventStoreError.unsupportedFeature
            }
        }
    }
}

