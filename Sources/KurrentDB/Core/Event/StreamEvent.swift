//
//  StreamEventData.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/2/11.
//
import Foundation

/// Batch of event records destined for a single stream, with an expected revision for optimistic concurrency.
///
/// ```swift
/// let event = try EventRecord(eventType: "order-placed", payload: .json(order))
/// let streamEvent = StreamEvent(stream: "orders", records: event)
/// ```
public struct StreamEvent: Sendable {
    /// Target stream identifier.
    public let streamIdentifier: StreamIdentifier

    /// Ordered records to append.
    public let records: [EventRecord]

    /// Required current stream revision; the append fails if the stream is at a different revision.
    public let expectedRevision: StreamRevision

    /// Creates a `StreamEvent` with a `StreamIdentifier` and an array of records.
    ///
    /// - Parameters:
    ///   - streamIdentifier: Target stream identifier.
    ///   - records: Ordered records to append.
    ///   - expectedRevision: Required current stream revision; defaults to `.any`.
    public init(stream streamIdentifier: StreamIdentifier, records: [EventRecord], expectedRevision: StreamRevision = .any) {
        self.streamIdentifier = streamIdentifier
        self.records = records
        self.expectedRevision = expectedRevision
    }

    /// Creates a `StreamEvent` with a stream name string and an array of records.
    ///
    /// - Parameters:
    ///   - streamName: Target stream name.
    ///   - records: Ordered records to append.
    ///   - expectedRevision: Required current stream revision; defaults to `.any`.
    public init(stream streamName: String, records: [EventRecord], expectedRevision: StreamRevision = .any) {
        streamIdentifier = .init(name: streamName)
        self.records = records
        self.expectedRevision = expectedRevision
    }
}

extension StreamEvent {
    /// Creates a `StreamEvent` with a `StreamIdentifier` and variadic records.
    ///
    /// - Parameters:
    ///   - streamIdentifier: Target stream identifier.
    ///   - records: One or more records to append, in order.
    ///   - expectedRevision: Required current stream revision; defaults to `.any`.
    public init(stream streamIdentifier: StreamIdentifier, records: EventRecord..., expectedRevision: StreamRevision = .any) {
        self.streamIdentifier = streamIdentifier
        self.records = records
        self.expectedRevision = expectedRevision
    }

    /// Creates a `StreamEvent` with a stream name string and variadic records.
    ///
    /// - Parameters:
    ///   - streamName: Target stream name.
    ///   - records: One or more records to append, in order.
    ///   - expectedRevision: Required current stream revision; defaults to `.any`.
    public init(stream streamName: String, records: EventRecord..., expectedRevision: StreamRevision = .any) {
        streamIdentifier = .init(name: streamName)
        self.records = records
        self.expectedRevision = expectedRevision
    }
}

extension StreamEvent {
    /// Creates a `StreamEvent` from variadic `EventData` values using a `StreamIdentifier`.
    ///
    /// - Parameters:
    ///   - streamIdentifier: Target stream identifier.
    ///   - eventData: One or more legacy `EventData` values to convert and append.
    ///   - expectedRevision: Required current stream revision; defaults to `.any`.
    /// - Throws: `KurrentError` if any `EventData` cannot be converted to an `EventRecord`.
    public init(stream streamIdentifier: StreamIdentifier, eventData: EventData..., expectedRevision: StreamRevision = .any) throws {
        self.streamIdentifier = streamIdentifier
        records = try eventData.map {
            try .init(eventData: $0)
        }
        self.expectedRevision = expectedRevision
    }

    /// Creates a `StreamEvent` from variadic `EventData` values using a stream name string.
    ///
    /// - Parameters:
    ///   - streamName: Target stream name.
    ///   - eventData: One or more legacy `EventData` values to convert and append.
    ///   - expectedRevision: Required current stream revision; defaults to `.any`.
    /// - Throws: `KurrentError` if any `EventData` cannot be converted to an `EventRecord`.
    public init(stream streamName: String, eventData: EventData..., expectedRevision: StreamRevision = .any) throws {
        streamIdentifier = .init(name: streamName)
        records = try eventData.map {
            try .init(eventData: $0)
        }
        self.expectedRevision = expectedRevision
    }
}
