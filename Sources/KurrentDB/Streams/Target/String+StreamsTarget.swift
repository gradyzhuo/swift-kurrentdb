//
//  String+StreamsTarget.swift
//  KurrentDB
//

/// Allows `String` to be used directly as a stream target.
extension String: SpecifiedStreamTarget {
    /// The stream identifier derived from this string value.
    public var identifier: StreamIdentifier {
        .init(name: self)
    }
}
