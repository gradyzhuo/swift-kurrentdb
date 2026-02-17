# User management

Manage user accounts in KurrentDB, including creating users, updating profiles, changing passwords, and controlling account status.

## Creating a client

User management operations require administrative credentials.

```swift
let settings = ClientSettings.localhost()
    .authenticated(.credentials(username: "admin", password: "changeit"))
let client = KurrentDBClient(settings: settings)
```

For TLS-enabled or remote clusters:

```swift
// Multi-node localhost with TLS
let settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
    .secure(true)
    .tlsVerifyCert(false)
    .authenticated(.credentials(username: "admin", password: "changeit"))
    .cerificate(path: "/path/to/ca.crt")
let client = KurrentDBClient(settings: settings)

// Remote cluster (secure: true by default)
let settings = ClientSettings.remote(
    "node1.example.com:2113",
    "node2.example.com:2113",
    "node3.example.com:2113"
).authenticated(.credentials(username: "admin", password: "changeit"))
let client = KurrentDBClient(settings: settings)

// Remote without TLS
let settings = ClientSettings.remote(
    "node1.example.com:2113", secure: false
).authenticated(.credentials(username: "admin", password: "changeit"))
let client = KurrentDBClient(settings: settings)
```

## User groups

KurrentDB uses ``UserGroup`` for role-based access control. There are two built-in system groups and support for custom application-defined groups.

### Built-in groups

| Enum Case | Raw Value | Description | Permissions |
|-----------|-----------|-------------|-------------|
| `.admins` | `$admins` | Full cluster administration | Read/write access to all streams including system streams (`$`-prefixed), user management, and all operational commands |
| `.ops` | `$ops` | Operational activities | Scavenge, shutdown, and other operational tasks. Standard user access for data streams (non-`$` streams) |

### Custom groups

Use `.custom("name")` for application-defined groups with specific stream or projection permissions.

```swift
// Built-in groups
let adminGroup: UserGroup = .admins
let opsGroup: UserGroup = .ops

// Custom groups
let writers: UserGroup = .custom("order-writers")
let readers: UserGroup = .custom("report-readers")

// String literal (auto-maps "$admins" and "$ops" to built-in cases)
let group: UserGroup = "$admins"  // equivalent to .admins
```

## Create a user

Creates a new user account with the specified credentials, profile information, and group memberships.

```swift
let user = try await client.users.create(
    loginName: "jane_doe",
    password: "secure_password_123",
    fullName: "Jane Doe",
    groups: [.ops, .custom("order-writers")]
)

if let user {
    print("Created user: \(user.loginName)")
    print("Groups: \(user.groups)")
}
```

You can also use variadic syntax:

```swift
let user = try await client.users.create(
    loginName: "admin_user",
    password: "secure_password_123",
    fullName: "Admin User",
    groups: .admins, .ops
)
```

## Get user details

Retrieves detailed information about a specific user.

```swift
let detailsStream = try await client.user("jane_doe").details()
for try await detail in detailsStream {
    print("User: \(detail.loginName)")
    print("Full name: \(detail.fullName)")
    print("Groups: \(detail.groups)")     // [UserGroup]
    print("Disabled: \(detail.disabled)")
}
```

## Enable a user

Enables a previously disabled user account, restoring authentication and access.

```swift
try await client.user("jane_doe").enable()
```

## Disable a user

Disables a user account, immediately revoking the ability to authenticate.

```swift
try await client.user("jane_doe").disable()
```

## Update user information

Updates user profile information such as full name and group memberships.

```swift
// Update full name only
try await client.user("jane_doe")
    .update(fullName: "Jane Smith", with: "current_password")

// Update with options
let options = Users<SpecifiedUserTarget>.Update.Options()
    .set(fullName: "Jane Smith")
    .set(groups: .admins, .custom("developers"))

try await client.user("jane_doe")
    .update(password: "current_password", options: options)
```

## Change password

Changes a user's password after verifying the current password. This is typically used for user-initiated password changes.

```swift
try await client.user("jane_doe")
    .change(password: "new_secure_password", origin: "old_password")
```

## Reset password

Administrative operation to reset a user's password without knowledge of the current password. Requires `.admins` group membership.

```swift
try await client.user("jane_doe")
    .reset(password: "temporary_password_123")
```

## Target-based API

The `users` property and `user(_:)` method return a type-safe ``Users`` actor scoped to the given target. The target determines which operations are available at compile time.

### Available targets

| Method | Target | Available Operations |
|--------|--------|---------------------|
| `client.users` | `AllUsersTarget` | `create(loginName:password:fullName:groups:)` |
| `client.user("name")` | `SpecifiedUserTarget` | `details()`, `enable()`, `disable()`, `update(...)`, `change(...)`, `reset(...)` |

### Type safety

The target-based design provides compile-time guarantees:

```swift
// client.users — can create users
try await client.users.create(loginName: "user", ...)    // ✓ Allowed
try await client.users.enable()                           // ✗ Compile error

// client.user("user") — can control a specific user
try await client.user("user").details()    // ✓ Allowed
try await client.user("user").enable()     // ✓ Allowed
try await client.user("user").create(...)  // ✗ Compile error
```

## Architecture

For details on the target-based design of the Users API, see <doc:UsersTarget-design>.
