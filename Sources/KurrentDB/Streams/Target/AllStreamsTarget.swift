//
//  AllStreamsTarget.swift
//  KurrentDB
//

/// Target representing the global `$all` stream that contains every event in the database.
public struct AllStreamsTarget: StreamsTarget {}

extension StreamsTarget where Self == AllStreamsTarget {
    /// Target for the `$all` stream.
    public static var all: AllStreamsTarget {
        .init()
    }
}
