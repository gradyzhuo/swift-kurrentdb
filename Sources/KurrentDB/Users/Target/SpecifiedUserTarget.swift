//
//  SpecifiedUserTarget.swift
//  KurrentDB
//

/// A target representing operations on a specific user identified by login name.
///
/// Supports account management operations via `UserControllable`:
/// retrieving details, enabling/disabling, updating profile, and managing credentials.
///
/// - SeeAlso: `UserControllable`, `UsersTarget`, `AllUsersTarget`
public struct SpecifiedUserTarget: UserControllable {
    /// The unique login name identifying the target user.
    public let loginName: String

    public init(loginName: String) {
        self.loginName = loginName
    }
}

extension UsersTarget where Self == SpecifiedUserTarget {
    /// Creates a target for a specific user identified by login name.
    public static func specified(_ loginName: String) -> SpecifiedUserTarget {
        .init(loginName: loginName)
    }
}
