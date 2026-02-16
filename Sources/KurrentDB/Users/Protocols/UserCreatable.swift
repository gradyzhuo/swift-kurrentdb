//
//  UserCreatable.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2026/2/15.
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
/// ## Available Operations
///
/// Targets conforming to this protocol can:
/// - Create new user accounts with credentials and group memberships
/// - Initialize user profiles with full names and metadata
/// - Assign users to groups and roles
///
/// - SeeAlso: `UserControllable`, `AllUsersTarget`
public protocol UserCreatable: UsersTarget {}
