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

/// A gRPC service for managing user accounts.
///
/// `Users` provides an interface for user account management, allowing operations such as creating users,
/// retrieving user details, enabling/disabling accounts, updating user information, and managing passwords.
///
/// ## Usage
///
/// Creating a `Users` service client:
/// ```swift
/// let usersService = Users(settings: clientSettings)
/// try await usersService.create(loginName: "john_doe", password: "securePass123", fullName: "John Doe", groups: "admin", "user")
/// ```
///
/// Retrieving user details:
/// ```swift
/// let userDetails = try await usersService.details(loginName: "john_doe")
/// ```
///
/// Changing a user's password:
/// ```swift
/// try await usersService.change(password: "newSecurePass456", origin: "securePass123", to: "john_doe")
/// ```
///
/// - Note: This service is built on top of **gRPC** and requires a valid `ClientSettings` configuration.
public struct Users: GRPCConcreteService {
    
    /// The underlying client type used for gRPC communication.
    package typealias UnderlyingClient = EventStore_Client_Users_Users.Client<HTTP2ClientTransport.Posix>

    /// The client settings required for establishing a gRPC connection.
    public private(set) var settings: ClientSettings
    
    /// The gRPC call options.
    public var callOptions: CallOptions
    
    /// The event loop group handling asynchronous tasks.
    public let eventLoopGroup: EventLoopGroup

    /// Initializes a `Users` instance with the given settings.
    ///
    /// - Parameters:
    ///   - settings: The client settings for gRPC communication.
    ///   - callOptions: The gRPC call options, defaulting to `.defaults`.
    ///   - eventLoopGroup: The event loop group, defaulting to a shared multi-threaded group.
    internal init(settings: ClientSettings, callOptions: CallOptions = .defaults, eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup) {
        self.settings = settings
        self.callOptions = callOptions
        self.eventLoopGroup = eventLoopGroup
    }
}

extension Users {
    // MARK: - Create Actions

    /// Creates a new user account.
    ///
    /// - Parameters:
    ///   - loginName: The username for the new account.
    ///   - password: The password for the new account.
    ///   - fullName: The full name of the user.
    ///   - groups: A list of groups to which the user belongs.
    /// - Returns: The created `UserDetails` if successful, otherwise `nil`.
    public func create(loginName: String, password: String, fullName: String, groups: String...) async throws -> UserDetails? {
        let usecase = Create(loginName: loginName, password: password, fullName: fullName, groups: groups)

        _ = try await usecase.perform(settings: settings, callOptions: callOptions)

        let responses = try await details(loginName: loginName)
        return try await responses.first { _ in true }
    }

    // MARK: - Details Actions

    /// Retrieves the details of a specific user.
    ///
    /// - Parameter loginName: The username of the user.
    /// - Returns: An asynchronous stream of `UserDetails` values.
    public func details(loginName: String) async throws -> AsyncThrowingStream<UserDetails, Error> {
        let usecase = Details(loginName: loginName)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    /// Enables a user account.
    ///
    /// - Parameter loginName: The username of the account to enable.
    public func enable(loginName: String) async throws {
        let usecase = Enable(loginName: loginName)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    /// Disables a user account.
    ///
    /// - Parameter loginName: The username of the account to disable.
    public func disable(loginName: String) async throws {
        let usecase = Disable(loginName: loginName)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    /// Updates user information.
    ///
    /// - Parameters:
    ///   - loginName: The username of the user to update.
    ///   - password: The password required for authentication.
    ///   - options: The update options containing the new values.
    public func update(loginName: String, password: String, options: Update.Options) async throws {
        let usecase = Update(loginName: loginName, password: password, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    /// Updates a user's full name.
    ///
    /// - Parameters:
    ///   - fullName: The new full name of the user.
    ///   - loginName: The username of the user.
    ///   - password: The password required for authentication.
    public func update(fullName: String, to loginName: String, with password: String) async throws {
        let options = Users.Update.Options()
            .set(fullName: fullName)
        try await update(loginName: loginName, password: password, options: options)
    }
    
    /// Changes a user's password.
    ///
    /// - Parameters:
    ///   - newPassword: The new password.
    ///   - currentPassword: The current password.
    ///   - loginName: The username of the user.
    public func change(password newPassword: String, origin currentPassword: String, to loginName: String) async throws {
        let usecase = ChangePassword(loginName: loginName, currentPassword: currentPassword, newPassword: newPassword)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    /// Resets a user's password.
    ///
    /// - Parameters:
    ///   - newPassword: The new password.
    ///   - loginName: The username of the user.
    public func reset(password newPassword: String, loginName: String) async throws {
        let usecase = ResetPassword(loginName: loginName, newPassword: newPassword)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
}
