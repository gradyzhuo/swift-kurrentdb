//
//  AllStreams.swift
//  KurrentDB
//

/// Represents the global `$all` stream containing all events across all streams.
public struct AllStreams: StreamsTarget {}

extension StreamsTarget where Self == AllStreams {
    /// Returns a target representing the `$all` stream.
    public static var all: AllStreams {
        .init()
    }
}
