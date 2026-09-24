# Client pools

Borrow a client for one of several independent KurrentDB instances with the `KurrentDBPool` library.

## Overview

`KurrentDBPool` is a separate library in this package, built mainly for tests: it holds a pool of **independent** KurrentDB instances — separate databases, not nodes of one cluster — and lends each caller an instance nobody else is using. Tests that need a database to themselves can run side by side without stepping on each other's data.

Add the library to the targets that use it:

<!-- snippet:skip -->
```swift
.testTarget(
    name: "MyAppTests",
    dependencies: [
        .product(name: "KurrentDB", package: "swift-kurrentdb"),
        .product(name: "KurrentDBPool", package: "swift-kurrentdb"),
    ]
)
```

## Configuring the pool

The pool reads its instances from the `KURRENTDB_POOL_URLS` environment variable: a JSON array of connection strings.

```
KURRENTDB_POOL_URLS=["kurrentdb://admin:changeit@localhost:2114?tls=false","kurrentdb://admin:changeit@localhost:2115?tls=false"]
```

A JSON array rather than a separator character, because a password may contain any character except `:` and `@`.

> Important: If the variable is set but isn't a JSON array of strings, or one of its connection strings doesn't parse, the process stops with a fatal error. The message names the entry's position but never echoes the connection string, so passwords don't end up in logs.

If the variable isn't set, the pool is empty.

## Borrowing a client

`withBorrowedClient(_:)` borrows an instance, passes it to your closure as a `BorrowedClient`, and gives it back when the closure returns or throws:

```swift
let count = try await withBorrowedClient { borrowed in
    let client = borrowed.client

    try await client.streams(specified: "orders").append(events: [eventData])

    var count = 0
    for try await _ in try await client.streams(specified: "orders").read() {
        count += 1
    }
    return count
}

guard let count else {
    // No instance was available: the pool is empty, or none of the
    // instances tried was reachable.
    return
}
print(count)
```

The result is optional: `withBorrowedClient` returns `nil` without calling your closure when it can't lend an instance.

### How an instance is chosen

- When every instance is busy, the first attempt waits until one is given back.
- Before lending an instance, the pool checks that it's reachable along the same path real calls use — gossip discovery, endpoint resolution and server feature detection — so a borrowed client works on its first call.
- An unreachable instance is set aside and the next idle one is tried, up to `maxAttempts` (3 by default). Later attempts don't wait: if no other instance is idle, the call gives up and returns `nil`. Instances set aside are returned to the pool when the call ends, to be checked again next time.

Pass `numberOfThreads` to size the borrowed client's event loop group, and `maxAttempts` to change how many instances are tried:

```swift
let result = try await withBorrowedClient(numberOfThreads: 2, maxAttempts: 5) { borrowed in
    try await borrowed.client.streams(specified: "orders").append(events: [eventData])
}
```

## After giving it back

Giving an instance back only returns it to the pool; the borrowed ``KurrentDBClient`` itself keeps working. Don't keep using it outside the closure — another caller may be using the same instance. If you keep the `BorrowedClient`, check `isGivenBack` before using it.
