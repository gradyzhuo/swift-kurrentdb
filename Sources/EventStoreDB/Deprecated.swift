//
//  Deprecated.swift
//  KurrentDB
//
//  Created by 卓俊諺 on 2025/1/29.
//
import KurrentDB

@available(*, deprecated, renamed: "KurrentError")
public typealias EventStoreError = KurrentError

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
extension PersistentSubscriptions.Subscription: AsyncSequence {
    public typealias Element = PersistentSubscription.EventResult
    public typealias AsyncIterator = AsyncThrowingStream<Element, Error>.AsyncIterator

    public func makeAsyncIterator() -> AsyncThrowingStream<Element, any Error>.AsyncIterator {
        events.makeAsyncIterator()
    }
}

extension KurrentDB.StreamRevision {
    public static func revision(_ value: UInt64) -> Self {
        .at(value)
    }
}

extension Streams.ReadResponse {
    @available(*, deprecated, message: "content is unnecessary, handle response content by ReadResponse itself.")
    public var content: Self {
        self
    }
}

extension ReadEvent {
    @available(*, deprecated, renamed: "link")
    public var linkedRecordedEvent: RecordedEvent? {
        link
    }

    @available(*, deprecated, renamed: "event")
    public var recordedEvent: RecordedEvent {
        record
    }
}
