//
//  UserControllable.swift
//  KurrentDB
//

/// A protocol marking user targets that support control operations on specific users.
///
/// Types conforming to `UserControllable` can perform administrative and management operations
/// on individual user accounts: viewing details, modifying account status, updating
/// profile information, and managing credentials.
///
/// ## Conforming Types
///
/// - `SpecifiedUserTarget`: Can control a specific user identified by login name
///
/// - SeeAlso: `UserCreatable`, `SpecifiedUserTarget`
public protocol UserControllable: UsersTarget {
    /// The login name uniquely identifying the user to control.
    var loginName: String { get }
}
