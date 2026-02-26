//
//  UsersTarget.swift
//  KurrentDB
//

/// A protocol representing a target for user management operations in KurrentDB.
///
/// The target identifies the scope of user operations and constrains which
/// methods are available at compile time through protocol conformance:
/// - `UserCreatable`: targets that support creating new users (`AllUsersTarget`)
/// - `UserControllable`: targets that support managing a specific user (`SpecifiedUserTarget`)
///
/// - SeeAlso: `UserCreatable`, `UserControllable`, `AllUsersTarget`, `SpecifiedUserTarget`
public protocol UsersTarget: Sendable {}
