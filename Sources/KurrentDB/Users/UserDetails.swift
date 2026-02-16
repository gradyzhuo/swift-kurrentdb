//
//  UserDetails.swift
//  KurrentUsers
//
//  Created by 卓俊諺 on 2025/1/16.
//
import Foundation
import GRPCEncapsulates

/// Represents the details of a user.
///
/// `UserDetails` contains important information about a user, including their username, full name,
/// associated groups, last update timestamp, and whether the account is disabled.
///
/// - Note: This struct is designed to be used as a part of user management functionalities, typically for
/// retrieving and updating user information in a user management system.
///
/// ## Usage Example:
/// ```swift
/// let user = UserDetails(loginName: "john_doe", fullName: "John Doe", groups: ["admin", "user"],
///                        lastUpdated: Date(), disabled: false)
/// ```
///
/// - SeeAlso: `Users` for the service to manage users and their details.
public struct UserDetails: Sendable {
    /// The login name (username) of the user.
    public var loginName: String

    /// The full name of the user.
    public var fullName: String

    /// The list of groups the user belongs to.
    public var groups: [UserGroup]

    /// The last updated timestamp of the user’s details.
    public var lastUpdated: Date

    /// A flag indicating whether the user’s account is disabled.
    public var disabled: Bool

    /// Initializes a `UserDetails` instance with the given user details.
    ///
    /// - Parameters:
    ///   - loginName: The login name (username) of the user.
    ///   - fullName: The full name of the user.
    ///   - groups: The groups the user belongs to.
    ///   - lastUpdated: The date when the user’s details were last updated.
    ///   - disabled: A flag indicating whether the user’s account is disabled.
    public init(loginName: String, fullName: String, groups: [UserGroup], lastUpdated: Date, disabled: Bool) {
        self.loginName = loginName
        self.fullName = fullName
        self.groups = groups
        self.lastUpdated = lastUpdated
        self.disabled = disabled
    }
}

extension UserDetails {
    /// Initializes a `UserDetails` instance from the output of a `Users` service's method.
    ///
    /// This initializer converts the underlying message received from the `Users.UnderlyingClient.UnderlyingService.Method.Details.Output.UserDetails`
    /// into a `UserDetails` struct.
    ///
    /// - Parameters:
    ///   - message: The user details message from the service method output.
    /// - Throws: An error if the transformation fails.
    package init(from message: Users.UnderlyingClient.UnderlyingService.Method.Details.Output.UserDetails) throws {
        self.init(
            loginName: message.loginName,
            fullName: message.fullName,
            groups: message.groups.map { .init(rawValue: $0) },
            lastUpdated: .init(timeIntervalSince1970: .init(message.lastUpdated.ticksSinceEpoch)),
            disabled: message.disabled
        )
    }
}
