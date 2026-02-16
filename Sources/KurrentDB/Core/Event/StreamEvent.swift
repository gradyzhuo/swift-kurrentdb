//
//  StreamEventData.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2026/2/11.
//
import Foundation

/// A value that groups one or more events to be appended to a specific stream,
/// along with the expected stream revision for optimistic concurrency control.
///
/// Use `StreamEvent` when you want to write a batch of events atomically to a
/// particular stream. The `expectedRevision` indicates what revision the stream
/// must currently be at for the append to succeed. If the actual revision does
/// not match, the write should fail to prevent lost updates.
///
/// Topics:
/// - Stream identity:
///   - `streamIdentifier`: Identifies the target stream for the events.
/// - Event payloads:
///   - `events`: The ordered collection of event data to append.
/// - Concurrency control:
///   - `expectedRevision`: The stream revision the writer expects before appending,
///     typically used for optimistic concurrency checks. A default of `.any` can be
///     used when no precondition is required.
///
/// Thread safety:
/// - `StreamEvent` is an immutable, `Sendable` value type and can be safely
///   shared across threads and tasks.
///
/// Initialization:
/// - `init(streamIdentifier:events:expectedRevision:)`
///   - Parameters:
///     - streamIdentifier: The unique identifier of the target stream.
///     - events: The events to append, in the order they should be persisted.
///     - expectedRevision: The required current revision of the stream for the
///       append to succeed. Defaults to `.any`.
public struct StreamEvent: Sendable {
    public let streamIdentifier: StreamIdentifier
    public let records: [EventRecord]
    public let expectedRevision: StreamRevision

    public init(stream streamIdentifier: StreamIdentifier, records: [EventRecord], expectedRevision: StreamRevision = .any) {
        self.streamIdentifier = streamIdentifier
        self.records = records
        self.expectedRevision = expectedRevision
    }

    public init(stream streamName: String, records: [EventRecord], expectedRevision: StreamRevision = .any) {
        streamIdentifier = .init(name: streamName)
        self.records = records
        self.expectedRevision = expectedRevision
    }
}

extension StreamEvent {
    public init(stream streamIdentifier: StreamIdentifier, records: EventRecord..., expectedRevision: StreamRevision = .any) {
        self.streamIdentifier = streamIdentifier
        self.records = records
        self.expectedRevision = expectedRevision
    }

    public init(stream streamName: String, records: EventRecord..., expectedRevision: StreamRevision = .any) {
        streamIdentifier = .init(name: streamName)
        self.records = records
        self.expectedRevision = expectedRevision
    }
}

extension StreamEvent {
    public init(stream streamIdentifier: StreamIdentifier, eventData: EventData..., expectedRevision: StreamRevision = .any) throws {
        self.streamIdentifier = streamIdentifier
        records = try eventData.map {
            try .init(eventData: $0)
        }
        self.expectedRevision = expectedRevision
    }

    public init(stream streamName: String, eventData: EventData..., expectedRevision: StreamRevision = .any) throws {
        streamIdentifier = .init(name: streamName)
        records = try eventData.map {
            try .init(eventData: $0)
        }
        self.expectedRevision = expectedRevision
    }
}
