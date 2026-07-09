//
//  ConsistencyCheck.swift
//  swift-kurrentdb
//
//  Pre-commit consistency check for AppendRecords (Dynamic Consistency Boundary).
//

import Foundation

/// A pre-commit consistency check used by ``Streams/AppendRecords`` (Dynamic Consistency Boundary).
///
/// A check asserts that a stream is at an expected revision or lifecycle state **before** the
/// append commits. Unlike the write side, a check may reference any stream — including streams the
/// append does not write to — enabling DCB patterns where a decision depends on multiple streams
/// but only produces events for a subset.
///
/// ```swift
/// // Only checks seat-A1's revision; writes nothing to it.
/// try await client.multiStreams.appendRecords(
///     events: [StreamEvent(stream: "booking-123", records: bookedEvent)],
///     checks: [.streamState("seat-A1", .at(7))]
/// )
/// ```
public struct ConsistencyCheck: Sendable {
    /// The stream whose state is asserted.
    public let streamIdentifier: StreamIdentifier

    /// The expected revision or lifecycle state of the stream before commit.
    public let expectedState: StreamRevision

    /// Creates a consistency check for a stream identifier.
    public init(stream streamIdentifier: StreamIdentifier, expectedState: StreamRevision) {
        self.streamIdentifier = streamIdentifier
        self.expectedState = expectedState
    }

    /// Creates a consistency check for a stream name.
    public init(stream streamName: String, expectedState: StreamRevision) {
        streamIdentifier = .init(name: streamName)
        self.expectedState = expectedState
    }

    /// Asserts a stream is at a specific revision or lifecycle state before commit.
    public static func streamState(_ streamName: String, _ expectedState: StreamRevision) -> ConsistencyCheck {
        .init(stream: streamName, expectedState: expectedState)
    }

    /// Asserts a stream is at a specific revision or lifecycle state before commit.
    public static func streamState(_ streamIdentifier: StreamIdentifier, _ expectedState: StreamRevision) -> ConsistencyCheck {
        .init(stream: streamIdentifier, expectedState: expectedState)
    }
}

extension StreamRevision {
    /// Encodes this revision rule as the v2 `expected_state` value used by consistency checks.
    ///
    /// v2 `ExpectedRevisionConstants`: `SINGLE_EVENT = 0`, `NO_STREAM = -1`, `ANY = -2`, `EXISTS = -4`.
    /// A concrete revision `n` is encoded as `n`.
    package var v2ExpectedState: Int64 {
        switch self {
        case .any: -2
        case .noStream: -1
        case .streamExists: -4
        case let .at(revision): Int64(revision)
        }
    }
}
