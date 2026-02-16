# UsersTarget design

The target-based architecture for user management operations, providing compile-time type safety through protocol composition.

## Overview

The Users API uses a target-based design pattern, consistent with ``StreamsTarget``, ``ProjectionsTarget``, and ``OperationsTarget``. Each target type determines the scope and available operations at compile time.

## Protocol hierarchy

```
UsersTarget (Protocol)
├── UserCreatable (Protocol)
│   └── AllUsersTarget (Struct)
└── UserControllable (Protocol)
    └── SpecifiedUserTarget (Struct)
```

## Capability protocols

Each capability protocol defines a specific scope of operations:

| Protocol | Target | Purpose | Operations |
|----------|--------|---------|------------|
| ``UserCreatable`` | ``AllUsersTarget`` | Create new user accounts | `create(loginName:password:fullName:groups:)` |
| ``UserControllable`` | ``SpecifiedUserTarget`` | Manage a specific user account (requires `loginName`) | `details()`, `enable()`, `disable()`, `update(...)`, `change(password:origin:)`, `reset(password:)` |

## Design decisions

### Why two capability protocols?

User operations naturally fall into two distinct categories with different scopes:

1. **UserCreatable** — Creating a user is a system-wide operation. No user identity exists yet, so there is no specific resource to target.
2. **UserControllable** — All other operations require targeting a specific user by login name (details, enable, disable, update, password management).

This separation mirrors the create/control pattern in ``OperationsTarget`` (`ScavengeOperations` vs `ActiveScavenge`), where creation is a broad-scope operation and control targets a specific resource.

### Why separate AllUsersTarget and SpecifiedUserTarget?

User operations have two distinct phases:

1. **Creation** — Creating a new user (no login name exists yet, the caller provides one)
2. **Management** — Controlling an existing user (requires login name to identify the target)

Separating them ensures you cannot accidentally call `enable()` without specifying which user, and cannot call `create()` on a single-user target.

## Static factory methods

Each target has a static factory method on ``UsersTarget`` via `where Self ==` extensions:

```swift
client.users                         // Users<AllUsersTarget>
client.user("jane_doe")              // Users<SpecifiedUserTarget>
```

## Type safety

The target-based design provides compile-time guarantees that prevent invalid operation combinations:

```swift
// ✓ Correct: Create a user via AllUsersTarget
try await client.users.create(
    loginName: "jane_doe",
    password: "secure_password",
    fullName: "Jane Doe",
    groups: [.ops]
)

// ✗ Compile error: Cannot create from SpecifiedUserTarget
try await client.user("jane_doe").create(loginName: "other", ...)

// ✓ Correct: Control a specific user
try await client.user("jane_doe").details()
try await client.user("jane_doe").enable()
try await client.user("jane_doe").disable()
try await client.user("jane_doe").change(password: "new", origin: "old")

// ✗ Compile error: Cannot call details() on AllUsersTarget
try await client.users.details()

// ✗ Compile error: Cannot call enable() on AllUsersTarget
try await client.users.enable()
```

## Comparison with other targets

| Concept | StreamsTarget | UsersTarget | ProjectionsTarget | OperationsTarget |
|---------|--------------|-------------|-------------------|------------------|
| Base Protocol | `StreamsTarget` | `UsersTarget` | `ProjectionsTarget` | `OperationsTarget` |
| Creation Target | — | `AllUsersTarget` | `ContinuousTarget`, `OneTimeTarget`, `TransientTarget` | `ScavengeOperations` |
| Control Target | `SpecifiedStream` | `SpecifiedUserTarget` | `NameTarget` | `ActiveScavenge` |
| System Target | `AllStreams` | — | `AnyProjectionsTarget` | `SystemOperations` |
| Service Actor | `Streams<Target>` | `Users<Target>` | `Projections<Target>` | `Operations<Target>` |

## File structure

```
Sources/KurrentDB/Users/
├── UsersTarget.swift                      # Base protocol + static factory methods
├── Protocols/
│   ├── UserCreatable.swift                # User creation capability
│   └── UserControllable.swift             # User control capability
├── Targets/
│   ├── AllUsersTarget.swift               # System-wide user creation target
│   └── SpecifiedUserTarget.swift          # Specific user management target
├── Users.swift                            # Generic Users<Target> actor
├── UserDetails.swift                      # User details response type
├── UserGroup.swift                        # Type-safe user group enum
└── Usecase/
    ├── Users.Create.swift
    ├── Users.Details.swift
    ├── Users.Enable.swift
    ├── Users.Disable.swift
    ├── Users.Update.swift
    ├── Users.ChangePassword.swift
    └── Users.ResetPassword.swift
```
