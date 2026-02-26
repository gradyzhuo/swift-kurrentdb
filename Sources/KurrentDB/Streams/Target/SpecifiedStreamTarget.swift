//
//  SpecifiedStreamTarget.swift
//  KurrentDB
//

/// A protocol for stream targets that have a specific identifier.
///
/// Conforming types must provide a `StreamIdentifier` to uniquely identify the stream.
public protocol SpecifiedStreamTarget: StreamsTarget {
    /// The identifier for the stream.
    var identifier: StreamIdentifier { get }
}
