//
//  Deprecated.swift
//  KurrentDB
//
//  Created by 卓俊諺 on 2025/1/29.
//
import KurrentDB

public enum Stream {
    @available(*, deprecated, message: "please use StreamIdentifier from KurrentCore instead.")
    public typealias Identifier = StreamIdentifier

    @available(*, deprecated, message: "please use StreamMetadata from KurrentCore instead.")
    public typealias Metadata = StreamMetadata

    @available(*, deprecated, message: "please use StreamPosition from KurrentCore instead.")
    public typealias Position = StreamPosition

    @available(*, deprecated, message: "please use StreamRevision from KurrentCore instead.")
    public typealias Revision = StreamRevision

    @available(*, deprecated, message: "please use StreamSelector from KurrentCore instead.")
    public typealias Selector = StreamSelector
}


@available(*, deprecated, message: "The PersistentSubscriptions.Subscription as AsyncSequence is deprecated. Please use PersistentSubscriptions.Subscription.events instead.")
extension PersistentSubscriptions.Subscription: AsyncSequence{
    public typealias Element = PersistentSubscription.EventResult
    public typealias AsyncIterator = AsyncThrowingStream<Element, Error>.AsyncIterator
    
    public func makeAsyncIterator() -> AsyncThrowingStream<Element, any Error>.AsyncIterator {
        return events.makeAsyncIterator()
    }
}

@available(*, deprecated, message: "The Streams.Subscription as AsyncSequence is deprecated. Please use Streams.Subscription.events instead.")
extension Streams.Subscription: AsyncSequence{
    
    @available(*, deprecated, message: "The Streams.Subscription.EventAppeared is deprecated.")
    public struct EventAppeared {
        public let event: ReadEvent

        init(event: ReadEvent) {
            self.event = event
        }
    }
    
    @available(*, deprecated, message: "The Streams.Subscription.EventIterator is deprecated.")
    public struct AsyncIterator: AsyncIteratorProtocol {
        public typealias Element = EventAppeared

        var iterator: AsyncThrowingStream<ReadEvent, Error>.AsyncIterator

        init(iterator: AsyncThrowingStream<ReadEvent, Error>.AsyncIterator) {
            self.iterator = iterator
        }

        public mutating func next() async throws -> EventAppeared? {
            while true {
                if let event = try await iterator.next(){
                    return .init(event: event)
                }
            }
        }
    }

    public func makeAsyncIterator() -> AsyncIterator {
        let iterator = events.makeAsyncIterator()
        return .init(iterator: iterator)
    }
    
}

extension Streams.ReadResponse {
    @available(*, deprecated, message: "content is unnecessary, handle response content by ReadResponse itself.")
    public var content: Self {
        get{
            self
        }
    }
}

extension ReadEvent {
    @available(*, deprecated, renamed: "link")
    public var linkedRecordedEvent: RecordedEvent?{
        get{
            link
        }
    }
    
    @available(*, deprecated, renamed: "event")
    public var recordedEvent: RecordedEvent{
        get{
            record
        }
    }
}
