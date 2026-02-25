//
//  KurrentDBClient+V1Users.swift
//  swift-kurrentdb
//
//  Compatibility layer — convenience methods for user management.
//  Prefer the target-based API: client.users, client.user(_:)
//

import KurrentDB

@available(*, deprecated, message: "Use the target-based API instead: client.users, client.user(_:)")
extension KurrentDBClient {
    /// Creates a new user account in the KurrentDB system.
    public func createUser(loginName: String, password: String, fullName: String, groups: [UserGroup]) async throws(KurrentError) -> UserDetails? {
        try await users.create(loginName: loginName, password: password, fullName: fullName, groups: groups)
    }

    /// Creates a new user account with variadic group parameters.
    public func createUser(loginName: String, password: String, fullName: String, groups: UserGroup...) async throws(KurrentError) -> UserDetails? {
        try await users.create(loginName: loginName, password: password, fullName: fullName, groups: groups)
    }

    /// Retrieves detailed information about a specific user.
    public func getUserDetails(loginName: String) async throws(KurrentError) -> AsyncThrowingStream<UserDetails, Error> {
        try await user(loginName).details()
    }

    /// Enables a user account, allowing authentication and access.
    public func enableUser(loginName: String) async throws(KurrentError) {
        try await user(loginName).enable()
    }

    /// Disables a user account, preventing authentication and access.
    public func disableUser(loginName: String) async throws(KurrentError) {
        try await user(loginName).disable()
    }

    /// Updates a user's information with the specified options.
    public func updateUser(loginName: String, password: String, options: Users<SpecifiedUserTarget>.Update.Options) async throws(KurrentError) {
        try await user(loginName).update(password: password, options: options)
    }

    /// Updates a user's full name.
    public func updateUserFullName(fullName: String, loginName: String, password: String) async throws(KurrentError) {
        try await user(loginName).update(fullName: fullName, with: password)
    }

    /// Changes a user's password.
    public func changeUserPassword(loginName: String, currentPassword: String, newPassword: String) async throws(KurrentError) {
        try await user(loginName).change(password: newPassword, origin: currentPassword)
    }

    /// Resets a user's password without requiring the current password.
    public func resetUserPassword(loginName: String, newPassword: String) async throws(KurrentError) {
        try await user(loginName).reset(password: newPassword)
    }
}
