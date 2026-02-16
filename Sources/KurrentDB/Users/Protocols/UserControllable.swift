//
//  UserControllable.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2026/2/15.
//

/// A protocol marking user targets that support control operations on specific users.
///
/// Types conforming to `UserControllable` can perform administrative and management operations
/// on individual user accounts. This includes viewing user details, modifying account status,
/// updating user information, and managing credentials.
///
/// ## Required Property
///
/// Conforming types must provide a `loginName` property that uniquely identifies the target user.
///
/// ## Conforming Types
///
/// - `SpecifiedUserTarget`: Can control a specific user identified by login name
///
/// ## Available Operations
///
/// Targets conforming to this protocol can:
/// - Retrieve detailed user information
/// - Enable or disable user accounts
/// - Update user profile information (full name, groups)
/// - Change user passwords (requires current password)
/// - Reset user passwords (administrative operation)
///
/// ## Example
///
/// ```swift
/// let target = UsersTarget.user("john_doe")
/// let users = Users(target: target, selector: selector, ...)
///
/// // Retrieve user details
/// let details = try await users.details()
///
/// // Disable the user account
/// try await users.disable()
///
/// // Change password
/// try await users.change(password: "newPass", origin: "oldPass")
/// ```
///
/// - SeeAlso: `UserCreatable`, `SpecifiedUserTarget`
public protocol UserControllable: UsersTarget {
    /// The login name uniquely identifying the user to control.
    var loginName: String { get }
}
