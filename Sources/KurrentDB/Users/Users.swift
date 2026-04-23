//
//  Users.swift
//  KurrentUsers
//
//  Created by Grady Zhuo on 2023/11/28.
//
import Foundation
import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix
import Logging
import NIO

/// gRPC service for managing KurrentDB user accounts scoped to a specific target.
public final class Users<Target: UsersTarget>: GRPCConcreteService {
    package typealias UnderlyingClient = EventStore_Client_Users_Users.Client<HTTP2ClientTransport.Posix>

    internal let selector: NodeSelector
    internal let callOptions: CallOptions
    internal let eventLoopGroup: EventLoopGroup

    /// The target specifying which users this service operates on.
    public let target: Target

    init(target: Target, selector: NodeSelector, callOptions: CallOptions = .defaults, eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup) {
        self.target = target
        self.selector = selector
        self.callOptions = callOptions
        self.eventLoopGroup = eventLoopGroup
    }
}

// MARK: - User Creation Operations

extension Users where Target: UserCreatable {
    /// Creates a new user account and returns the resulting user details.
    ///
    /// ```swift
    /// let user = try await client.users.create(
    ///     loginName: "jane_doe",
    ///     password: "secure_password_123",
    ///     fullName: "Jane Doe",
    ///     groups: ["$admins", "developers"]
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - loginName: Unique login name for the new account.
    ///   - password: Password for the account.
    ///   - fullName: Full display name for the user.
    ///   - groups: Group memberships to assign to the user.
    /// - Returns: The newly created user's details, or `nil` if retrieval fails.
    /// - Throws: `KurrentError.alreadyExists` if the login name is already taken.
    ///   `KurrentError.accessDenied` if the caller lacks user creation permissions.
    ///   `KurrentError.invalidArgument` if the login name or password is invalid.
    public func create(loginName: String, password: String, fullName: String, groups: [UserGroup]) async throws(KurrentError) -> UserDetails? {
        let usecase = Create(loginName: loginName, password: password, fullName: fullName, groups: groups)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)

        // Retrieve and return the created user's details
        let userTarget = SpecifiedUserTarget(loginName: loginName)
        let userService = Users<SpecifiedUserTarget>(target: userTarget, selector: selector, callOptions: callOptions, eventLoopGroup: eventLoopGroup)
        let responses = try await userService.details()
        do {
            return try await responses.first { _ in true }
        } catch {
            throw .serverError("create user with loginName: \(loginName) failed, error: \(error)")
        }
    }

    /// Creates a new user account using variadic group parameters.
    ///
    /// - Parameters:
    ///   - loginName: Unique login name for the new account.
    ///   - password: Password for the account.
    ///   - fullName: Full display name for the user.
    ///   - groups: Variadic group memberships to assign to the user.
    /// - Returns: The newly created user's details, or `nil` if retrieval fails.
    /// - Throws: `KurrentError.alreadyExists`, `KurrentError.accessDenied`, `KurrentError.invalidArgument`.
    public func create(loginName: String, password: String, fullName: String, groups: UserGroup...) async throws(KurrentError) -> UserDetails? {
        try await create(loginName: loginName, password: password, fullName: fullName, groups: groups)
    }
}

// MARK: - User Control Operations

extension Users where Target: UserControllable {
    /// Retrieves details for the target user as an asynchronous stream.
    ///
    /// - Returns: An async stream of `UserDetails` values for the target user.
    /// - Throws: `KurrentError.notFound` if the user does not exist.
    ///   `KurrentError.accessDenied` if the caller lacks permission to view user details.
    public func details() async throws(KurrentError) -> AsyncThrowingStream<UserDetails, Error> {
        let usecase = Details(loginName: target.loginName)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Enables the target user account, restoring authentication access.
    ///
    /// - Throws: `KurrentError.notFound` if the user does not exist.
    ///   `KurrentError.accessDenied` if the caller lacks user management permissions.
    public func enable() async throws(KurrentError) {
        let usecase = Enable(loginName: target.loginName)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Disables the target user account, preventing authentication.
    ///
    /// - Throws: `KurrentError.notFound` if the user does not exist.
    ///   `KurrentError.accessDenied` if the caller lacks user management permissions.
    public func disable() async throws(KurrentError) {
        let usecase = Disable(loginName: target.loginName)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Updates the target user's profile with the specified options.
    ///
    /// - Parameters:
    ///   - password: Current password for authentication.
    ///   - options: Options specifying which profile fields to modify.
    /// - Throws: `KurrentError.notFound` if the user does not exist.
    ///   `KurrentError.accessDenied` if authentication fails or permissions are insufficient.
    ///   `KurrentError.invalidArgument` if the update options are invalid.
    public func update(password: String, options: Update.Options) async throws(KurrentError) {
        let usecase = Update(loginName: target.loginName, password: password, options: options)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Updates the target user's full name.
    ///
    /// - Parameters:
    ///   - fullName: The new full name for the user.
    ///   - password: Current password for authentication.
    /// - Throws: `KurrentError.notFound`, `KurrentError.accessDenied`, `KurrentError.invalidArgument`.
    public func update(fullName: String, with password: String) async throws(KurrentError) {
        let options = Update.Options().set(fullName: fullName)
        try await update(password: password, options: options)
    }

    /// Changes the target user's password after verifying the current one.
    ///
    /// - Parameters:
    ///   - newPassword: The new password to set.
    ///   - currentPassword: Current password for verification.
    /// - Throws: `KurrentError.notFound` if the user does not exist.
    ///   `KurrentError.accessDenied` if the current password is incorrect.
    ///   `KurrentError.invalidArgument` if the new password does not meet requirements.
    public func change(password newPassword: String, origin currentPassword: String) async throws(KurrentError) {
        let usecase = ChangePassword(loginName: target.loginName, currentPassword: currentPassword, newPassword: newPassword)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Resets the target user's password without requiring the current password.
    ///
    /// - Parameter newPassword: The new password to set for the user.
    /// - Throws: `KurrentError.notFound` if the user does not exist.
    ///   `KurrentError.accessDenied` if the caller lacks administrative permissions.
    ///   `KurrentError.invalidArgument` if the new password does not meet requirements.
    public func reset(password newPassword: String) async throws(KurrentError) {
        let usecase = ResetPassword(loginName: target.loginName, newPassword: newPassword)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }
}
