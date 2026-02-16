//
//  UserGroup.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2026/2/16.
//

/// Represents a user group in KurrentDB for role-based access control.
///
/// KurrentDB uses groups to define user permissions. There are two built-in system groups
/// and support for custom application-defined groups.
///
/// ## Built-in Groups
///
/// | Group | Description |
/// |-------|-------------|
/// | `$admins` | Full access to everything, including user management and all system streams |
/// | `$ops` | Can perform operational activities (scavenge, shutdown) but restricted to user streams for data access |
///
/// ## Custom Groups
///
/// Applications can define custom groups for fine-grained access control on specific streams
/// or projections.
///
/// ## Usage
///
/// ```swift
/// // Using built-in groups
/// try await client.users.create(
///     loginName: "admin-user",
///     password: "secure_password",
///     fullName: "Admin User",
///     groups: [.admins]
/// )
///
/// // Using operational group
/// try await client.users.create(
///     loginName: "ops-user",
///     password: "secure_password",
///     fullName: "Ops User",
///     groups: [.ops]
/// )
///
/// // Using custom groups
/// try await client.users.create(
///     loginName: "app-user",
///     password: "secure_password",
///     fullName: "App User",
///     groups: [.ops, .custom("order-writers"), .custom("report-readers")]
/// )
/// ```
public enum UserGroup: Sendable, Equatable, Hashable {
    /// The `$admins` group with full access to everything in KurrentDB.
    ///
    /// Members have full read and write access to all streams, including
    /// protected system streams (those starting with `$`), and can manage
    /// other users and perform all operational commands.
    case admins

    /// The `$ops` group for operational activities.
    ///
    /// Members can perform operational activities like scavenge and shutdown,
    /// but have standard user access for data streams. They have read/write
    /// access to user streams (non-`$` streams) by default, but restricted
    /// access to system streams and user management functions.
    case ops

    /// A custom application-defined group.
    ///
    /// - Parameter name: The group name. Should not start with `$` to avoid
    ///   conflicts with system groups.
    case custom(String)

    /// The raw string value sent to KurrentDB.
    public var rawValue: String {
        switch self {
        case .admins:
            "$admins"
        case .ops:
            "$ops"
        case let .custom(name):
            name
        }
    }

    /// Creates a `UserGroup` from a raw string value.
    ///
    /// Automatically maps `$admins` and `$ops` to their respective enum cases,
    /// and treats all other values as custom groups.
    ///
    /// - Parameter rawValue: The group name string.
    public init(rawValue: String) {
        switch rawValue {
        case "$admins":
            self = .admins
        case "$ops":
            self = .ops
        default:
            self = .custom(rawValue)
        }
    }
}

extension UserGroup: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}
