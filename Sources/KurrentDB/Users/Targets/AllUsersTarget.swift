//
//  AllUsersTarget.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2026/2/15.
//

/// A target representing operations on all users in the KurrentDB system.
///
/// `AllUsersTarget` is used for operations that apply to the entire user base rather than
/// specific individual users. This target type supports user creation operations, allowing
/// administrators to add new user accounts to the system.
///
/// ## Capabilities
///
/// This target conforms to `UserCreatable`, enabling:
/// - Creating new user accounts
/// - Initializing user credentials and profiles
/// - Assigning users to groups and roles
///
/// ## Usage
///
/// ```swift
/// let allUsers = Users(target: .all, selector: selector, ...)
///
/// // Create a new user
/// let newUser = try await allUsers.create(
///     loginName: "jane_doe",
///     password: "securePassword",
///     fullName: "Jane Doe",
///     groups: ["$admins", "developers"]
/// )
/// ```
///
/// - SeeAlso: `UserCreatable`, `UsersTarget`, `SpecifiedUserTarget`
public struct AllUsersTarget: UserCreatable {
    /// Convenience property for creating an all-users target.
    public static var all: AllUsersTarget {
        AllUsersTarget()
    }

    /// Initializes a target representing all users.
    public init() {}
}
