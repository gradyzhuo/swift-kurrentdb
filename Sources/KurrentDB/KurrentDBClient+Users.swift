//
//  KurrentDBClient+Users.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2026/2/13.
//

// MARK: - Internal User Management Factory Methods

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

// MARK: - User Management Operations

extension KurrentDBClient {
    /// Creates a new user account in the KurrentDB system.
    ///
    /// Creates a new user with the specified credentials, profile information, and group memberships.
    /// This operation requires administrative privileges and is typically used for provisioning
    /// service accounts, application users, or team member access.
    ///
    /// ## User Roles and Permissions
    ///
    /// KurrentDB supports role-based access control:
    /// - **$admins**: Full cluster administration privileges
    /// - **$ops**: Operational tasks (scavenges, shutdowns)
    /// - **Custom Roles**: Application-defined groups with specific stream/projection permissions
    ///
    /// ## Password Requirements
    ///
    /// Passwords should meet minimum complexity requirements:
    /// - Minimum length (typically 8+ characters)
    /// - Mix of uppercase, lowercase, numbers, and special characters
    /// - Avoid common passwords and dictionary words
    ///
    /// ## Security Best Practices
    ///
    /// - Avoid embedding credentials in code; use environment variables or secret stores
    /// - Regularly rotate service account passwords
    /// - Audit user creation and permission changes
    /// - Use principle of least privilege for group assignments
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Create a service account
    /// let newUser = try await client.createUser(
    ///     loginName: "order-service",
    ///     password: "secure_password_123",
    ///     fullName: "Order Processing Service",
    ///     groups: ["$ops", "order-writers"]
    /// )
    ///
    /// if let user = newUser {
    ///     print("Created user: \(user.loginName)")
    ///     print("Groups: \(user.groups)")
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - loginName: Unique username for the new account. Must not already exist.
    ///   - password: Password for the account. Should meet complexity requirements.
    ///   - fullName: Full display name for the user.
    ///   - groups: Array of group names to assign the user to.
    ///
    /// - Returns: The created user's details if successful, or `nil` if retrieval fails.
    ///
    /// - Throws: `KurrentError.alreadyExists` if a user with the login name already exists.
    ///   `KurrentError.accessDenied` if the caller lacks user creation permissions ($admins group).
    ///   `KurrentError.invalidArgument` if the login name or password is invalid.
    ///
    /// - Note: Only users in the `$admins` group can create new users.
    ///
    /// - Warning: User creation affects authentication and authorization. Test permission
    ///   configurations thoroughly before deploying to production.
    ///
    /// - SeeAlso: `getUserDetails(loginName:)`, `updateUser(loginName:password:options:)`
    public func createUser(loginName: String, password: String, fullName: String, groups: [UserGroup]) async throws(KurrentError) -> UserDetails? {
        try await users.create(loginName: loginName, password: password, fullName: fullName, groups: groups)
    }

    /// Creates a new user account with variadic group parameters.
    ///
    /// Convenience overload that accepts groups as variadic parameters instead of an array.
    ///
    /// - Parameters:
    ///   - loginName: Unique username for the new account.
    ///   - password: Password for the account.
    ///   - fullName: Full display name for the user.
    ///   - groups: Variadic list of groups to assign the user to.
    ///
    /// - Returns: The created user's details if successful, or `nil` if retrieval fails.
    ///
    /// - Throws: `KurrentError.alreadyExists`, `KurrentError.accessDenied`, `KurrentError.invalidArgument`
    public func createUser(loginName: String, password: String, fullName: String, groups: UserGroup...) async throws(KurrentError) -> UserDetails? {
        try await createUser(loginName: loginName, password: password, fullName: fullName, groups: groups)
    }

    /// Retrieves detailed information about a specific user.
    ///
    /// Returns comprehensive information about the user including login name, full name,
    /// group memberships, and account status.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let detailsStream = try await client.getUserDetails(loginName: "john_doe")
    /// for try await userDetail in detailsStream {
    ///     print("User: \(userDetail.loginName)")
    ///     print("Full name: \(userDetail.fullName)")
    ///     print("Groups: \(userDetail.groups)")
    ///     print("Disabled: \(userDetail.disabled)")
    /// }
    /// ```
    ///
    /// - Parameter loginName: The unique login name of the user to query.
    ///
    /// - Returns: An asynchronous stream of `UserDetails` values.
    ///
    /// - Throws: `KurrentError.notFound` if the user does not exist.
    ///   `KurrentError.accessDenied` if the caller lacks permissions to view user details.
    ///
    /// - SeeAlso: `createUser(loginName:password:fullName:groups:)`
    public func getUserDetails(loginName: String) async throws(KurrentError) -> AsyncThrowingStream<UserDetails, Error> {
        try await user(loginName).details()
    }

    /// Enables a user account, allowing authentication and access.
    ///
    /// Enables a previously disabled user account, restoring the user's ability to authenticate
    /// and access the system according to their assigned permissions.
    ///
    /// ## Example
    ///
    /// ```swift
    /// try await client.enableUser(loginName: "john_doe")
    /// ```
    ///
    /// - Parameter loginName: The unique login name of the user to enable.
    ///
    /// - Throws: `KurrentError.notFound` if the user does not exist.
    ///   `KurrentError.accessDenied` if the caller lacks user management permissions.
    ///
    /// - SeeAlso: `disableUser(loginName:)`
    public func enableUser(loginName: String) async throws(KurrentError) {
        try await user(loginName).enable()
    }

    /// Disables a user account, preventing authentication and access.
    ///
    /// Disables a user account, immediately revoking the user's ability to authenticate.
    /// The account remains in the system but cannot be used until re-enabled.
    ///
    /// ## Example
    ///
    /// ```swift
    /// try await client.disableUser(loginName: "john_doe")
    /// ```
    ///
    /// - Parameter loginName: The unique login name of the user to disable.
    ///
    /// - Throws: `KurrentError.notFound` if the user does not exist.
    ///   `KurrentError.accessDenied` if the caller lacks user management permissions.
    ///
    /// - Warning: Disabling a user immediately revokes all access. Ensure this is the intended
    ///   action before proceeding.
    ///
    /// - SeeAlso: `enableUser(loginName:)`
    public func disableUser(loginName: String) async throws(KurrentError) {
        try await user(loginName).disable()
    }

    /// Updates a user's information with the specified options.
    ///
    /// Updates user profile information such as full name and group memberships. Requires
    /// the user's current password for authentication.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let options = Users<SpecifiedUserTarget>.Update.Options()
    ///     .set(fullName: "Jane Smith")
    ///     .set(groups: ["$admins", "developers"])
    ///
    /// try await client.updateUser(
    ///     loginName: "jane_doe",
    ///     password: "current_password",
    ///     options: options
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - loginName: The unique login name of the user to update.
    ///   - password: The user's current password for authentication.
    ///   - options: Update options specifying which fields to modify.
    ///
    /// - Throws: `KurrentError.notFound` if the user does not exist.
    ///   `KurrentError.accessDenied` if authentication fails or permissions are insufficient.
    ///   `KurrentError.invalidArgument` if the update options are invalid.
    ///
    /// - SeeAlso: `updateUserFullName(fullName:loginName:password:)`
    public func updateUser(loginName: String, password: String, options: Users<SpecifiedUserTarget>.Update.Options) async throws(KurrentError) {
        try await user(loginName).update(password: password, options: options)
    }

    /// Updates a user's full name.
    ///
    /// Convenience method to update only the user's full name.
    ///
    /// ## Example
    ///
    /// ```swift
    /// try await client.updateUserFullName(
    ///     fullName: "John Smith",
    ///     loginName: "john_doe",
    ///     password: "current_password"
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - fullName: The new full name for the user.
    ///   - loginName: The unique login name of the user to update.
    ///   - password: The user's current password for authentication.
    ///
    /// - Throws: `KurrentError.notFound`, `KurrentError.accessDenied`, `KurrentError.invalidArgument`
    ///
    /// - SeeAlso: `updateUser(loginName:password:options:)`
    public func updateUserFullName(fullName: String, loginName: String, password: String) async throws(KurrentError) {
        try await user(loginName).update(fullName: fullName, with: password)
    }

    /// Changes a user's password.
    ///
    /// Updates the user's password after verifying the current password. This operation
    /// requires knowledge of the current password and is typically used for user-initiated
    /// password changes.
    ///
    /// ## Example
    ///
    /// ```swift
    /// try await client.changeUserPassword(
    ///     loginName: "john_doe",
    ///     currentPassword: "old_password",
    ///     newPassword: "new_secure_password"
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - loginName: The unique login name of the user.
    ///   - currentPassword: The user's current password for verification.
    ///   - newPassword: The new password to set.
    ///
    /// - Throws: `KurrentError.notFound` if the user does not exist.
    ///   `KurrentError.accessDenied` if the current password is incorrect.
    ///   `KurrentError.invalidArgument` if the new password doesn't meet requirements.
    ///
    /// - SeeAlso: `resetUserPassword(loginName:newPassword:)`
    public func changeUserPassword(loginName: String, currentPassword: String, newPassword: String) async throws(KurrentError) {
        try await user(loginName).change(password: newPassword, origin: currentPassword)
    }

    /// Resets a user's password without requiring the current password.
    ///
    /// Administrative operation to reset a user's password without knowledge of the current
    /// password. This requires administrative privileges and is typically used when a user
    /// has forgotten their password or for account recovery.
    ///
    /// ## Example
    ///
    /// ```swift
    /// try await client.resetUserPassword(
    ///     loginName: "john_doe",
    ///     newPassword: "temporary_password_123"
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - loginName: The unique login name of the user.
    ///   - newPassword: The new password to set for the user.
    ///
    /// - Throws: `KurrentError.notFound` if the user does not exist.
    ///   `KurrentError.accessDenied` if the caller lacks administrative permissions.
    ///   `KurrentError.invalidArgument` if the new password doesn't meet requirements.
    ///
    /// - Warning: This operation bypasses password verification and requires administrative
    ///   privileges. Use only for legitimate account recovery scenarios.
    ///
    /// - SeeAlso: `changeUserPassword(loginName:currentPassword:newPassword:)`
    public func resetUserPassword(loginName: String, newPassword: String) async throws(KurrentError) {
        try await user(loginName).reset(password: newPassword)
    }
}
