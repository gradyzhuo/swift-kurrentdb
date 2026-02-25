//
//  KurrentDBClient+Users.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/2/13.
//

// MARK: - User Management Factory Methods

extension KurrentDBClient {
    /// Accesses the user management service for creating new users.
    ///
    /// ## Example
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
    /// - SeeAlso: `user(_:)`
    public var users: Users<AllUsersTarget> {
        .init(target: .all, selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
    }

    /// Returns a users interface for a specific user by login name.
    ///
    /// ## Example
    ///
    /// ```swift
    /// try await client.user("jane_doe").enable()
    /// try await client.user("jane_doe").details()
    /// ```
    ///
    /// - Parameter loginName: The unique login name of the target user.
    ///
    /// - Returns: A configured `Users<SpecifiedUserTarget>` instance for the specified user.
    ///
    /// - SeeAlso: `users`
    public func user(_ loginName: String) -> Users<SpecifiedUserTarget> {
        .init(target: .specified(loginName), selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
    }
}
