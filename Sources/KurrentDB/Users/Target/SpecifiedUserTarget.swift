//
//  SpecifiedUserTarget.swift
//  KurrentDB
//

/// Target scoped to a single user, enabling account management operations.
public struct SpecifiedUserTarget: UserControllable {
    /// Login name of the targeted user.
    public let loginName: String

    public init(loginName: String) {
        self.loginName = loginName
    }
}

extension UsersTarget where Self == SpecifiedUserTarget {
    /// Creates a target scoped to the user with the given login name.
    public static func specified(_ loginName: String) -> SpecifiedUserTarget {
        .init(loginName: loginName)
    }
}
