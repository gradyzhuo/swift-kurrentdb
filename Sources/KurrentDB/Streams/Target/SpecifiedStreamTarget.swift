//
//  SpecifiedStreamTarget.swift
//  KurrentDB
//

/// Stream target that identifies a single named stream.
public protocol SpecifiedStreamTarget: StreamsTarget {
    /// Unique identifier for the stream.
    var identifier: StreamIdentifier { get }
}
