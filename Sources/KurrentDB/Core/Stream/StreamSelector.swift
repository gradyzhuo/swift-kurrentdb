//
//  StreamSelector.swift
//  KurrentCore
//
//  Created by Grady Zhuo on 2024/3/23.
//

/// Selects either all streams or a specific stream target of type `T`.
public enum StreamSelector<T: Sendable>: Sendable {
    /// Targets every stream, equivalent to operating on `$all`.
    case all
    /// Targets a single stream identified by the associated value.
    case specified(T)
}
