//
//  Mode.swift
//  kurrentdb-swift
//
//  Created by Grady Zhuo on 2025/3/13.
//

extension Projection{
    public enum Mode: String, Sendable {
        case any
        @available(*, unavailable)
        case transient = "Transient"
        case continuous = "Continuous"
        case oneTime = "OneTime"
    }
}
