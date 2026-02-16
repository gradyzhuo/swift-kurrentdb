//
//  SpecifiedUserTarget.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2026/2/15.
//

/// A target representing operations on a specific user identified by login name.
///
/// `SpecifiedUserTarget` is used for operations that apply to an individual user account,
/// such as retrieving details, modifying account status, updating profile information, or
/// managing credentials. This target type requires a login name to identify the user.
///
/// ## Capabilities
///
/// This target conforms to `UserControllable`, enabling:
/// - Retrieving user details and account information
/// - Enabling or disabling the user account
/// - Updating user profile (full name, groups)
/// - Changing passwords (with current password verification)
/// - Resetting passwords (administrative operation)
///
/// ## Usage
///
/// ```swift
/// let userTarget = UsersTarget.user("john_doe")
/// let users = Users(target: userTarget, selector: selector, ...)
///
/// // Get user details
/// let details = try await users.details()
///
/// // Disable user account
/// try await users.disable()
///
/// // Update full name
/// try await users.update(fullName: "John Smith", with: "currentPassword")
///
/// // Change password
/// try await users.change(password: "newPassword", origin: "currentPassword")
/// ```
///
/// - SeeAlso: `UserControllable`, `UsersTarget`, `AllUsersTarget`
public struct SpecifiedUserTarget: UserControllable {
    /// The unique login name identifying the target user.
    public let loginName: String

    /// Initializes a target for a specific user.
    ///
    /// - Parameter loginName: The unique login name identifying the user.
    public init(loginName: String) {
        self.loginName = loginName
    }
}
