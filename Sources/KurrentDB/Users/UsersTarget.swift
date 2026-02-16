//
//  UsersTarget.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2026/2/15.
//

//
//  UsersTarget.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2026/2/15.
//

/// A protocol representing a target for user management operations in KurrentDB.
///
/// A **target** serves two key purposes in the Users API:
///
/// ## 1. Specifies the Operation Scope (Where)
///
/// The target identifies which users the operation applies to:
/// - `AllUsersTarget`: System-wide scope for user creation operations
/// - `SpecifiedUserTarget`: Single user scope for account management operations
///
/// ## 2. Constrains Available Operations (What)
///
/// Through protocol composition, different target types enable different capabilities:
/// - Targets conforming to `UserCreatable` support user creation operations
/// - Targets conforming to `UserControllable` support account management operations (enable, disable, update, password changes)
/// - The type system prevents invalid operations at compile time
///
/// ## Type Safety
///
/// This design provides compile-time guarantees that operations are only performed on appropriate user scopes:
///
/// ```swift
/// // Target specifies: system-wide scope (where)
/// // Target constrains: can create users (what)
/// let allUsers = Users(target: AllUsersTarget(), ...)
/// try await allUsers.create(loginName: "jane", ...)  // ✓ Allowed
/// try await allUsers.enable()                        // ✗ Compile error - no such method
///
/// // Target specifies: specific user "john_doe" (where)
/// // Target constrains: can manage this user (what)
/// let user = Users(target: SpecifiedUserTarget(loginName: "john_doe"), ...)
/// try await user.details()                           // ✓ Allowed
/// try await user.enable()                            // ✓ Allowed
/// try await user.disable()                           // ✓ Allowed
/// try await user.change(password: "new", origin: "old")  // ✓ Allowed
/// try await user.create(loginName: "jane", ...)      // ✗ Compile error - no such method
/// ```
///
/// ## Usage
///
/// Create targets using specific constructors:
///
/// ```swift
/// // For creating new users
/// let allUsers = AllUsersTarget()
/// let users = Users(target: allUsers, ...)
/// try await users.create(loginName: "jane_doe", password: "secure", ...)
///
/// // For managing a specific user
/// let userTarget = SpecifiedUserTarget(loginName: "john_doe")
/// let user = Users(target: userTarget, ...)
/// try await user.enable()
/// try await user.update(fullName: "John Smith", with: "password")
///
/// // Or use KurrentDBClient convenience methods (recommended)
/// try await client.createUser(loginName: "jane_doe", ...)
/// try await client.enableUser(loginName: "john_doe")
/// ```
///
/// ## Capability Protocols
///
/// - `UserCreatable`: Marks targets that can create new users (AllUsersTarget)
/// - `UserControllable`: Marks targets that can manage specific users (SpecifiedUserTarget)
///
/// - Note: This protocol is marked as `Sendable`, ensuring it can be safely used across concurrency contexts.
///
/// - SeeAlso: `UserCreatable`, `UserControllable`, `AllUsersTarget`, `SpecifiedUserTarget`
public protocol UsersTarget: Sendable {}

/// Extension providing a static factory method to create an `AllUsersTarget` instance.
extension UsersTarget where Self == AllUsersTarget {
    public static var all: AllUsersTarget {
        .init()
    }
}

/// Extension providing a static factory method to create a `SpecifiedUserTarget` instance.
extension UsersTarget where Self == SpecifiedUserTarget {
    public static func specified(_ loginName: String) -> SpecifiedUserTarget {
        .init(loginName: loginName)
    }
}
