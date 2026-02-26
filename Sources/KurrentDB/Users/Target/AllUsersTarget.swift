//
//  AllUsersTarget.swift
//  KurrentDB
//

/// A target representing operations on all users in the KurrentDB system.
///
/// Supports user creation operations via `UserCreatable`.
///
/// - SeeAlso: `UserCreatable`, `UsersTarget`, `SpecifiedUserTarget`
public struct AllUsersTarget: UserCreatable {
    public init() {}
}

extension UsersTarget where Self == AllUsersTarget {
    /// Returns a target representing all users (for creation operations).
    public static var all: AllUsersTarget {
        .init()
    }
}
