//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2024/3/23.
//

import Foundation
import GRPC
import GRPCSupport

extension PersistentSubscriptionsClient{
    public final class Subscriber: AsyncSequence {
        
        public typealias AsyncIterator = EventIterator
        public typealias Element = Read.EventResult
        
        public let eventIterator: EventIterator
        
        var subscriptionId: String?
        let requestStream: GRPCAsyncRequestStreamWriter<Read.Request.UnderlyingMessage>

        public init(readCall: GRPCAsyncBidirectionalStreamingCall<Read.Request.UnderlyingMessage, Read.Response.UnderlyingMessage>) async throws{
            
            self.requestStream = readCall.requestStream
            
            var iterator = readCall.responseStream.makeAsyncIterator()
            self.eventIterator = .init(responseStreamIterator: iterator)
            
            self.subscriptionId = if case .subscriptionConfirmation(let confirmation) = try await iterator.next()?.content{
                confirmation.subscriptionID
            }else{
                nil
            }
        }
        
        public func makeAsyncIterator() -> AsyncIterator {
            return eventIterator
        }
        
        internal func ack(eventIds: [UUID]) async throws {
            let id = subscriptionId?.data(using: .utf8) ?? .init()
            let handler = Ack.init(id: id, eventIds: eventIds)
            try await requestStream.send(handler.build())
        }

        public func ack(readEvents: [ReadEvent]) async throws{
            let eventIds = readEvents.map{
                return if let linked = $0.linkedRecordedEvent{
                    linked.id
                }else{
                    $0.recordedEvent.id
                }
            }
            try await ack(eventIds: eventIds)
        }

        public func ack(readEvents: ReadEvent ...) async throws {
            try await ack(readEvents: readEvents)
        }
        
        internal func nack(eventIds: [UUID], action: Nack.Action, reason: String) async throws {
            let handler: Nack = .init(id: .init(), eventIds: eventIds, action: action, reason: reason)
            try await requestStream.send(handler.build())
        }

        public func nack(readEvents: [ReadEvent], action: Nack.Action, reason: String) async throws{
            let eventIds = readEvents.map{
                return if let linked = $0.linkedRecordedEvent{
                    linked.id
                }else{
                    $0.recordedEvent.id
                }
            }
            try await nack(eventIds: eventIds, action: action, reason: reason)
        }

        public func nack(readEvents: ReadEvent ..., action: Nack.Action, reason: String) async throws {
            try await nack(readEvents: readEvents, action: action, reason: reason)
        }
        
        deinit {
            requestStream.finish()
        }
    }
}

extension PersistentSubscriptionsClient.Subscriber {
    public struct EventIterator: AsyncIteratorProtocol {

        public typealias Element = PersistentSubscriptionsClient.Subscriber.Element
        
        var responseStreamIterator: GRPCAsyncResponseStream<PersistentSubscriptionsClient.Read.Response.UnderlyingMessage>.AsyncIterator
        
        init(responseStreamIterator: GRPCAsyncResponseStream<PersistentSubscriptionsClient.Read.Response.UnderlyingMessage>.Iterator) {
            self.responseStreamIterator = responseStreamIterator
        }
        
        public mutating func next() async throws -> PersistentSubscriptionsClient.Read.EventResult? {
            
            while true {
                let response = try await responseStreamIterator.next()
                
                if case .event(let message) = response?.content{
                    let readEvent = try ReadEvent(message: message)
                    return .init(event: readEvent, retryCount: message.retryCount)
                }
            }
            
        }
        
    }
}
