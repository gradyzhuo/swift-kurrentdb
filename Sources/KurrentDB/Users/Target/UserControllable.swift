//
//  UserControllable.swift
//  KurrentDB
//

/// Capability protocol for user targets that support management operations on a specific account.
public protocol UserControllable: UsersTarget {
    /// Login name uniquely identifying the target user.
    var loginName: String { get }
}
