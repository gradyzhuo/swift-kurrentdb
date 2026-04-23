//
//  UserGroup.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2026/2/16.
//

/// Role-based access control group for a KurrentDB user.
///
/// KurrentDB ships with two built-in groups and supports arbitrary custom groups for
/// application-defined access control.
///
/// ```swift
/// // String literal initialisation (via ExpressibleByStringLiteral)
/// let group: UserGroup = "$admins"  // equivalent to .admins
///
/// // Assign built-in and custom groups when creating a user
/// try await client.users.create(
///     loginName: "jane_doe",
///     password: "secure_password",
///     fullName: "Jane Doe",
///     groups: [.admins, .ops, "order-writers"]
/// )
/// ```
public enum UserGroup: Sendable, Equatable, Hashable {
    /// The `$admins` group — full read/write access to all streams and user management.
    case admins

    /// The `$ops` group — permission to perform operational tasks such as scavenge and shutdown.
    case ops

    /// A custom application-defined group with the given name.
    case custom(String)

    /// Raw string value transmitted to KurrentDB (e.g., `"$admins"`, `"$ops"`, or a custom name).
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

    /// Creates a `UserGroup` from a raw string, mapping `"$admins"` and `"$ops"` to their enum cases.
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
