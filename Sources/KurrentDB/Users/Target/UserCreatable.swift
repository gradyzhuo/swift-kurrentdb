//
//  UserCreatable.swift
//  KurrentDB
//

/// A protocol marking user targets that support user creation operations.
///
/// Types conforming to `UserCreatable` can perform operations that create new user accounts
/// in the KurrentDB system. This capability is typically associated with targets representing
/// the entire user base rather than specific individual users.
///
/// ## Conforming Types
///
/// - `AllUsersTarget`: Can create new users in the system
///
/// - SeeAlso: `UserControllable`, `AllUsersTarget`
public protocol UserCreatable: UsersTarget {}
