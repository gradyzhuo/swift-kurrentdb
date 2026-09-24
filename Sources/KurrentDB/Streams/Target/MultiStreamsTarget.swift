//
//  MultiStreamsTarget.swift
//  KurrentDB
//

/// Target for writes across multiple streams: `append` (KurrentDB 25.1+), `appendRecords` (26.1+) and `batchAppend`.
public struct MultiStreamsTarget: StreamsTarget {}

extension StreamsTarget where Self == MultiStreamsTarget {
    /// Target for multi-stream batch operations.
    public static var multiple: MultiStreamsTarget {
        .init()
    }
}
