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

/// A gRPC service for managing user accounts with type-safe target-based operations.
///
/// `Users` provides a type-safe interface for user account management using target-based design.
/// Different operations are available depending on the target type:
///
/// ## Target Types
///
/// - **AllUsersTarget**: Operations on all users (e.g., creating new users)
/// - **SpecifiedUserTarget**: Operations on specific users (e.g., details, enable, disable, update)
///
/// ## Usage
///
/// Creating a new user:
/// ```swift
/// let allUsers = Users(target: .all, selector: selector, ...)
/// let newUser = try await allUsers.create(
///     loginName: "john_doe",
///     password: "securePass123",
///     fullName: "John Doe",
///     groups: ["$admins", "developers"]
/// )
/// ```
///
/// Managing a specific user:
/// ```swift
/// let userTarget = UsersTarget.user("john_doe")
/// let users = Users(target: userTarget, selector: selector, ...)
///
/// // Get user details
/// let details = try await users.details()
///
/// // Disable user
/// try await users.disable()
///
/// // Change password
/// try await users.change(password: "newPass", origin: "oldPass")
/// ```
///
/// - Note: This service is built on top of **gRPC** and requires proper authentication.
public actor Users<Target: UsersTarget>: GRPCConcreteService {
    /// The underlying client type used for gRPC communication.
    package typealias UnderlyingClient = EventStore_Client_Users_Users.Client<HTTP2ClientTransport.Posix>

    /// The node selector for routing requests to cluster nodes.
    public private(set) var selector: NodeSelector

    /// The gRPC call options.
    public var callOptions: CallOptions

    /// The event loop group handling asynchronous tasks.
    public let eventLoopGroup: EventLoopGroup

    /// The target specifying which users this service operates on.
    private(set) var target: Target

    /// Initializes a `Users` instance with a specific target.
    ///
    /// - Parameters:
    ///   - target: The users target specifying the scope of operations.
    ///   - selector: The node selector for cluster node routing.
    ///   - callOptions: The gRPC call options, defaulting to `.defaults`.
    ///   - eventLoopGroup: The event loop group, defaulting to a shared multi-threaded group.
    init(target: Target, selector: NodeSelector, callOptions: CallOptions = .defaults, eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup) {
        self.target = target
        self.selector = selector
        self.callOptions = callOptions
        self.eventLoopGroup = eventLoopGroup
    }
}

// MARK: - User Creation Operations

extension Users where Target: UserCreatable {
    /// Creates a new user account in the KurrentDB system.
    ///
    /// Creates a new user with the specified credentials, profile information, and group memberships.
    /// After successful creation, the user's details are retrieved and returned.
    ///
    /// ## Group Membership
    ///
    /// Users can be assigned to built-in or custom groups:
    /// - **$admins**: Full administrative privileges
    /// - **$ops**: Operational tasks (scavenges, shutdowns)
    /// - **Custom groups**: Application-defined access control groups
    ///
    /// ## Example
    ///
    /// ```swift
    /// let allUsers = Users(target: .all, selector: selector, ...)
    ///
    /// let newUser = try await allUsers.create(
    ///     loginName: "jane_doe",
    ///     password: "secure_password_123",
    ///     fullName: "Jane Doe",
    ///     groups: ["$admins", "developers"]
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - loginName: Unique username for the new account. Must not already exist.
    ///   - password: Password for the account. Should meet complexity requirements.
    ///   - fullName: Full display name for the user.
    ///   - groups: List of group names to assign the user to.
    ///
    /// - Returns: The created user's details if successful, or `nil` if retrieval fails.
    ///
    /// - Throws: `KurrentError.alreadyExists` if a user with the login name already exists.
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

    /// Creates a new user account with variadic group parameters.
    ///
    /// Convenience overload that accepts groups as variadic parameters instead of an array.
    ///
    /// - Parameters:
    ///   - loginName: Unique username for the new account.
    ///   - password: Password for the account.
    ///   - fullName: Full display name for the user.
    ///   - groups: Variadic list of group names to assign the user to.
    ///
    /// - Returns: The created user's details if successful, or `nil` if retrieval fails.
    ///
    /// - Throws: `KurrentError.alreadyExists`, `KurrentError.accessDenied`, `KurrentError.invalidArgument`
    public func create(loginName: String, password: String, fullName: String, groups: UserGroup...) async throws(KurrentError) -> UserDetails? {
        try await create(loginName: loginName, password: password, fullName: fullName, groups: groups)
    }
}

// MARK: - User Control Operations

extension Users where Target: UserControllable {
    /// Retrieves detailed information about the target user.
    ///
    /// Returns comprehensive information about the user including login name, full name,
    /// group memberships, and account status.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let users = Users(target: .user("john_doe"), selector: selector, ...)
    ///
    /// let detailsStream = try await users.details()
    /// for try await userDetail in detailsStream {
    ///     print("User: \(userDetail.loginName)")
    ///     print("Full name: \(userDetail.fullName)")
    ///     print("Groups: \(userDetail.groups)")
    /// }
    /// ```
    ///
    /// - Returns: An asynchronous stream of `UserDetails` values.
    ///
    /// - Throws: `KurrentError.notFound` if the user does not exist.
    ///   `KurrentError.accessDenied` if the caller lacks permissions to view user details.
    public func details() async throws(KurrentError) -> AsyncThrowingStream<UserDetails, Error> {
        let usecase = Details(loginName: target.loginName)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Enables the target user account, allowing authentication and access.
    ///
    /// Enables a previously disabled user account, restoring the user's ability to authenticate
    /// and access the system according to their assigned permissions.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let users = Users(target: .user("john_doe"), selector: selector, ...)
    /// try await users.enable()
    /// ```
    ///
    /// - Throws: `KurrentError.notFound` if the user does not exist.
    ///   `KurrentError.accessDenied` if the caller lacks user management permissions.
    public func enable() async throws(KurrentError) {
        let usecase = Enable(loginName: target.loginName)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Disables the target user account, preventing authentication and access.
    ///
    /// Disables a user account, immediately revoking the user's ability to authenticate.
    /// The account remains in the system but cannot be used until re-enabled.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let users = Users(target: .user("john_doe"), selector: selector, ...)
    /// try await users.disable()
    /// ```
    ///
    /// - Throws: `KurrentError.notFound` if the user does not exist.
    ///   `KurrentError.accessDenied` if the caller lacks user management permissions.
    public func disable() async throws(KurrentError) {
        let usecase = Disable(loginName: target.loginName)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Updates the target user's information with the specified options.
    ///
    /// Updates user profile information such as full name and group memberships. Requires
    /// the user's current password for authentication.
    ///
    /// - Parameters:
    ///   - password: The user's current password for authentication.
    ///   - options: Update options specifying which fields to modify.
    ///
    /// - Throws: `KurrentError.notFound` if the user does not exist.
    ///   `KurrentError.accessDenied` if authentication fails or permissions are insufficient.
    ///   `KurrentError.invalidArgument` if the update options are invalid.
    public func update(password: String, options: Update.Options) async throws(KurrentError) {
        let usecase = Update(loginName: target.loginName, password: password, options: options)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Updates the target user's full name.
    ///
    /// Convenience method to update only the user's full name.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let users = Users(target: .user("john_doe"), selector: selector, ...)
    /// try await users.update(fullName: "John Smith", with: "currentPassword")
    /// ```
    ///
    /// - Parameters:
    ///   - fullName: The new full name for the user.
    ///   - password: The user's current password for authentication.
    ///
    /// - Throws: `KurrentError.notFound`, `KurrentError.accessDenied`, `KurrentError.invalidArgument`
    public func update(fullName: String, with password: String) async throws(KurrentError) {
        let options = Update.Options().set(fullName: fullName)
        try await update(password: password, options: options)
    }

    /// Changes the target user's password.
    ///
    /// Updates the user's password after verifying the current password. This operation
    /// requires knowledge of the current password and is typically used for user-initiated
    /// password changes.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let users = Users(target: .user("john_doe"), selector: selector, ...)
    /// try await users.change(
    ///     password: "new_secure_password",
    ///     origin: "old_password"
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - newPassword: The new password to set.
    ///   - currentPassword: The user's current password for verification.
    ///
    /// - Throws: `KurrentError.notFound` if the user does not exist.
    ///   `KurrentError.accessDenied` if the current password is incorrect.
    ///   `KurrentError.invalidArgument` if the new password doesn't meet requirements.
    public func change(password newPassword: String, origin currentPassword: String) async throws(KurrentError) {
        let usecase = ChangePassword(loginName: target.loginName, currentPassword: currentPassword, newPassword: newPassword)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Resets the target user's password without requiring the current password.
    ///
    /// Administrative operation to reset a user's password without knowledge of the current
    /// password. This requires administrative privileges and is typically used when a user
    /// has forgotten their password or for account recovery.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let users = Users(target: .user("john_doe"), selector: selector, ...)
    /// try await users.reset(password: "temporary_password_123")
    /// ```
    ///
    /// - Parameter newPassword: The new password to set for the user.
    ///
    /// - Throws: `KurrentError.notFound` if the user does not exist.
    ///   `KurrentError.accessDenied` if the caller lacks administrative permissions.
    ///   `KurrentError.invalidArgument` if the new password doesn't meet requirements.
    public func reset(password newPassword: String) async throws(KurrentError) {
        let usecase = ResetPassword(loginName: target.loginName, newPassword: newPassword)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }
}
