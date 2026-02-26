//
//  MultiStreams.swift
//  KurrentDB
//

/// Represents a batch target for operations across multiple streams simultaneously.
public struct MultiStreams: StreamsTarget {}

extension StreamsTarget where Self == MultiStreams {
    /// Returns a target for batch multi-stream operations.
    public static var multiple: MultiStreams {
        .init()
    }
}
