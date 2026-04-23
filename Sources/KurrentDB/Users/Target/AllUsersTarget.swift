//
//  AllUsersTarget.swift
//  KurrentDB
//

/// Target representing the full user collection, enabling account creation operations.
public struct AllUsersTarget: UserCreatable {
    public init() {}
}

extension UsersTarget where Self == AllUsersTarget {
    /// Target representing all users, used for account creation.
    public static var all: AllUsersTarget {
        .init()
    }
}
