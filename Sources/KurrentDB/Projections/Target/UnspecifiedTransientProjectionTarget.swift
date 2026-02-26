//
//  UnspecifiedTransientProjectionTarget.swift
//  KurrentDB
//

/// A target for transient projections where the name is provided at creation time.
///
/// Does not conform to `ProjectionControlable` — use ``SpecifiedTransientProjectionTarget``
/// or ``NameTarget`` for control operations.
public struct UnspecifiedTransientProjectionTarget: ProjectionsTarget {
    public init() {}
}

extension ProjectionsTarget {
    /// Returns a target for creating transient projections without a pre-specified name.
    public static var anyTransient: UnspecifiedTransientProjectionTarget {
        .init()
    }
}
