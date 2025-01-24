//
//  User.swift
//  KurrentDB
//
//  Created by 卓俊諺 on 2025/1/16.
//
import Foundation
import GRPCEncapsulates

public struct UserDetails: Sendable {
    public var loginName: String
    public var fullName: String

    public var groups: [String]
    public var lastUpdated: Date
    public var disabled: Bool

    public init(loginName: String, fullName: String, groups: [String], lastUpdated: Date, disabled: Bool) {
        self.loginName = loginName
        self.fullName = fullName
        self.groups = groups
        self.lastUpdated = lastUpdated
        self.disabled = disabled
    }
}

extension UserDetails{
    public init(from message: Users.Client.UnderlyingService.Method.Details.Output.UserDetails) throws {
        self.init(
            loginName: message.loginName,
            fullName: message.fullName,
            groups: message.groups,
            lastUpdated: .init(timeIntervalSince1970: .init(message.lastUpdated.ticksSinceEpoch)),
            disabled: message.disabled
        )
    }
}
