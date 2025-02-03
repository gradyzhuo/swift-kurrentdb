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
    public typealias AsyncIterator = AsyncThrowingStream<Element, Error>.AsyncIterator
    
    public func makeAsyncIterator() -> AsyncThrowingStream<Element, any Error>.AsyncIterator {
        return events.makeAsyncIterator()
    }
}

@available(*, deprecated, message: "The Streams.Subscription as AsyncSequence is deprecated. Please use Streams.Subscription.events instead.")
extension Streams.Subscription: AsyncSequence{
    public typealias AsyncIterator = AsyncThrowingStream<Element, Error>.AsyncIterator
    
    public func makeAsyncIterator() -> AsyncThrowingStream<Element, any Error>.AsyncIterator {
        return events.makeAsyncIterator()
    }
    
}
