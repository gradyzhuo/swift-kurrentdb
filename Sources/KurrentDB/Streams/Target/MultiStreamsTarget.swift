//
//  MultiStreamsTarget.swift
//  KurrentDB
//

/// Represents a batch target for operations across multiple streams simultaneously.
public struct MultiStreamsTarget: StreamsTarget {}

extension StreamsTarget where Self == MultiStreamsTarget {
    /// Returns a target for batch multi-stream operations.
    public static var multiple: MultiStreamsTarget {
        .init()
    }
}
