# UsersTarget Design

This document explains the new target-based design for user management operations, following the same pattern as `StreamsTarget`.

## Architecture

### Protocol Hierarchy

```
UsersTarget (Protocol)
├── UserCreatable (Protocol)
│   └── AllUsersTarget (Struct)
└── UserControllable (Protocol)
    └── SpecifiedUserTarget (Struct)
```

### Capability Protocols

#### 1. UserCreatable

Marks targets that can create new users.

**Operations Available:**
- `create(loginName:password:fullName:groups:)` - Create new user accounts

**Conforming Types:**
- `AllUsersTarget` - Represents operations on all users

#### 2. UserControllable

Marks targets that can control specific users.

**Required Property:**
- `loginName: String` - The login name of the target user

**Operations Available:**
- `details()` - Retrieve user details
- `enable()` - Enable user account
- `disable()` - Disable user account
- `update(password:options:)` - Update user information
- `update(fullName:with:)` - Update user's full name
- `change(password:origin:)` - Change user password
- `reset(password:)` - Reset user password (admin operation)

**Conforming Types:**
- `SpecifiedUserTarget` - Represents a specific user

## Usage Examples

### Creating Users

```swift
// Using Users<AllUsersTarget> directly
let allUsers = Users(target: AllUsersTarget(), selector: selector, ...)
let newUser = try await allUsers.create(
    loginName: "jane_doe",
    password: "secure_password",
    fullName: "Jane Doe",
    groups: ["$admins", "developers"]
)

// Using KurrentDBClient convenience method
let user = try await client.createUser(
    loginName: "jane_doe",
    password: "secure_password",
    fullName: "Jane Doe",
    groups: ["$admins", "developers"]
)
```

### Controlling Specific Users

```swift
// Using Users<SpecifiedUserTarget> directly
let userTarget = SpecifiedUserTarget(loginName: "john_doe")
let users = Users(target: userTarget, selector: selector, ...)

// Get details
let detailsStream = try await users.details()
for try await detail in detailsStream {
    print("User: \(detail.loginName)")
}

// Enable/disable
try await users.enable()
try await users.disable()

// Update information
try await users.update(fullName: "John Smith", with: "password")

// Change password
try await users.change(password: "newPass", origin: "oldPass")

// Reset password (admin)
try await users.reset(password: "tempPass")

// Using KurrentDBClient convenience methods
try await client.getUserDetails(loginName: "john_doe")
try await client.enableUser(loginName: "john_doe")
try await client.disableUser(loginName: "john_doe")
try await client.updateUserFullName(fullName: "John Smith", loginName: "john_doe", password: "pass")
try await client.changeUserPassword(loginName: "john_doe", currentPassword: "old", newPassword: "new")
try await client.resetUserPassword(loginName: "john_doe", newPassword: "temp")
```

## Type Safety Benefits

The target-based design provides compile-time type safety:

1. **Create operations** are only available on `AllUsersTarget` (via `UserCreatable` protocol)
2. **Control operations** are only available on `SpecifiedUserTarget` (via `UserControllable` protocol)
3. Cannot accidentally call control operations without specifying a user
4. Cannot create users through a user-specific target

## File Structure

```
Sources/KurrentDB/Users/
├── UsersTarget.swift                      # Base protocol
├── Protocols/
│   ├── UserCreatable.swift                # Create capability protocol
│   └── UserControllable.swift             # Control capability protocol
├── Targets/
│   ├── AllUsersTarget.swift               # All users target
│   └── SpecifiedUserTarget.swift          # Specific user target
├── Users.swift                            # Generic Users<Target: UsersTarget> actor
└── KurrentDBClient+Users.swift            # Client extension with convenience methods
```

## Comparison with StreamsTarget

This design follows the same pattern as `StreamsTarget`:

| Concept | StreamsTarget | UsersTarget |
|---------|--------------|-------------|
| Base Protocol | `StreamsTarget` | `UsersTarget` |
| All Target | `AllStreams` | `AllUsersTarget` |
| Specific Target | `SpecifiedStream` | `SpecifiedUserTarget` |
| Capability Protocol 1 | `SpecifiedStreamTarget` | `UserCreatable` |
| Capability Protocol 2 | - | `UserControllable` |
| Service Actor | `Streams<Target>` | `Users<Target>` |

## Migration Notes

If you have existing code using the old `Users` API, here's how to migrate:

### Before (Old API)

```swift
let users = Users(selector: selector, ...)

// Create
try await users.create(loginName: "user", password: "pass", fullName: "Name", groups: "group1")

// Control
try await users.details(loginName: "user")
try await users.enable(loginName: "user")
try await users.disable(loginName: "user")
try await users.update(loginName: "user", password: "pass", options: options)
try await users.change(password: "new", origin: "old", to: "user")
try await users.reset(password: "new", loginName: "user")
```

### After (New API)

```swift
// For creation
let allUsers = Users(target: AllUsersTarget(), selector: selector, ...)
try await allUsers.create(loginName: "user", password: "pass", fullName: "Name", groups: ["group1"])

// For control
let userTarget = SpecifiedUserTarget(loginName: "user")
let users = Users(target: userTarget, selector: selector, ...)
try await users.details()
try await users.enable()
try await users.disable()
try await users.update(password: "pass", options: options)
try await users.change(password: "new", origin: "old")
try await users.reset(password: "new")

// Or use KurrentDBClient convenience methods (recommended)
try await client.createUser(loginName: "user", password: "pass", fullName: "Name", groups: ["group1"])
try await client.getUserDetails(loginName: "user")
try await client.enableUser(loginName: "user")
try await client.disableUser(loginName: "user")
try await client.updateUser(loginName: "user", password: "pass", options: options)
try await client.changeUserPassword(loginName: "user", currentPassword: "old", newPassword: "new")
try await client.resetUserPassword(loginName: "user", newPassword: "new")
```

## Benefits

1. **Type Safety**: Operations are restricted to appropriate target types at compile time
2. **Clear Intent**: Target type explicitly indicates the scope of operations
3. **Consistency**: Follows the same pattern as `StreamsTarget` for familiarity
4. **Extensibility**: Easy to add new target types or capabilities
5. **Documentation**: Self-documenting code through type system
6. **API Clarity**: Separate interfaces for creation vs. control operations

## Design Decisions

### Why Two Capability Protocols?

Unlike `StreamsTarget` which has one main capability protocol (`SpecifiedStreamTarget`), `UsersTarget` uses two:

1. **UserCreatable** - Creating users is a system-wide operation (AllUsersTarget)
2. **UserControllable** - Controlling users requires targeting a specific user (SpecifiedUserTarget)

This separation makes it impossible to accidentally call create operations on a specific user target or control operations without specifying which user.

### Why Not Use Static Factory Methods?

Initially considered using static factory methods on the protocol (like `.all` and `.user(_:)`), but this causes Swift compiler issues with protocol extensions. Instead:

- `AllUsersTarget` provides a `.all` static property
- `SpecifiedUserTarget` uses a regular initializer `SpecifiedUserTarget(loginName:)`
- Client convenience methods hide these details

This provides a clean API while avoiding compiler limitations.
