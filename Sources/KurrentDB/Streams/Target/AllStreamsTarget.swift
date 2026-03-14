//
//  AllStreamsTarget.swift
//  KurrentDB
//

/// Represents the global `$all` stream containing all events across all streams.
public struct AllStreamsTarget: StreamsTarget {}

extension StreamsTarget where Self == AllStreamsTarget {
    /// Returns a target representing the `$all` stream.
    public static var all: AllStreamsTarget {
        .init()
    }
}
