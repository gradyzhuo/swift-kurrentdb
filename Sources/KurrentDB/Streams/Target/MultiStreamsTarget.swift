//
//  MultiStreamsTarget.swift
//  KurrentDB
//

/// Target for batch append operations across multiple streams (requires KurrentDB 25.1+).
public struct MultiStreamsTarget: StreamsTarget {}

extension StreamsTarget where Self == MultiStreamsTarget {
    /// Target for multi-stream batch operations.
    public static var multiple: MultiStreamsTarget {
        .init()
    }
}
