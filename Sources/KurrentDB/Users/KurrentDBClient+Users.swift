//
//  KurrentDBClient+Users.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/2/13.
//

// MARK: - User Management Factory Methods

extension KurrentDBClient {
    /// Accesses the user management service for cluster-wide user operations (create, list).
    ///
    /// ```swift
    /// let user = try await client.users.create(
    ///     loginName: "jane_doe",
    ///     password: "secure_password",
    ///     fullName: "Jane Doe",
    ///     groups: ["$ops"]
    /// )
    /// ```
    ///
    /// - SeeAlso: ``user(_:)``
    public var users: Users<AllUsersTarget> {
        .init(target: .all, selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
    }

    /// Returns a users interface for a specific user by login name.
    ///
    /// Supports operations like enable, disable, update, change password, and details.
    ///
    /// ```swift
    /// let details = try await client.user("jane_doe").details()
    /// try await client.user("jane_doe").enable()
    /// ```
    ///
    /// - Parameter loginName: The unique login name of the target user.
    /// - Returns: A configured ``Users`` instance scoped to the specified user.
    public func user(_ loginName: String) -> Users<SpecifiedUserTarget> {
        .init(target: .specified(loginName), selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
    }
}
