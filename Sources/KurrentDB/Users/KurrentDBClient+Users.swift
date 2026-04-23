//
//  KurrentDBClient+Users.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/2/13.
//

// MARK: - User Management Factory Methods

extension KurrentDBClient {
    /// User management service for cluster-wide operations such as account creation.
    ///
    /// ```swift
    /// let user = try await client.users.create(
    ///     loginName: "jane_doe",
    ///     password: "secure_password",
    ///     fullName: "Jane Doe",
    ///     groups: ["$ops"]
    /// )
    /// ```
    public var users: Users<AllUsersTarget> {
        .init(target: .all, selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
    }

    /// Returns a user management interface scoped to the specified login name.
    ///
    /// ```swift
    /// let details = try await client.user("jane_doe").details()
    /// try await client.user("jane_doe").enable()
    /// ```
    ///
    /// - Parameter loginName: The unique login name of the target user.
    /// - Returns: A ``Users`` instance scoped to the specified user.
    public func user(_ loginName: String) -> Users<SpecifiedUserTarget> {
        .init(target: .specified(loginName), selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
    }
}
