//
//  UserDetails.swift
//  KurrentUsers
//
//  Created by 卓俊諺 on 2025/1/16.
//
import Foundation
import GRPCEncapsulates

/// Snapshot of a KurrentDB user account returned by the Users service.
public struct UserDetails: Sendable {
    /// Unique login name identifying the user.
    public var loginName: String

    /// Display name of the user.
    public var fullName: String

    /// Groups the user belongs to.
    public var groups: [UserGroup]

    /// Timestamp of the most recent update to this user record.
    public var lastUpdated: Date

    /// Indicates whether the account is currently disabled.
    public var disabled: Bool

    /// Creates a `UserDetails` value with the given field values.
    ///
    /// - Parameters:
    ///   - loginName: Unique login name for the user.
    ///   - fullName: Display name of the user.
    ///   - groups: Groups the user belongs to.
    ///   - lastUpdated: Date the user record was last modified.
    ///   - disabled: Whether the account is currently disabled.
    public init(loginName: String, fullName: String, groups: [UserGroup], lastUpdated: Date, disabled: Bool) {
        self.loginName = loginName
        self.fullName = fullName
        self.groups = groups
        self.lastUpdated = lastUpdated
        self.disabled = disabled
    }
}

extension UserDetails {
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
