# Getting started

Connect your application to KurrentDB.

## Getting the library

### Swift Package Manager

Add the package dependency to your `Package.swift`:

<!-- snippet:skip -->
```swift
dependencies: [
    .package(url: "https://github.com/gradyzhuo/swift-kurrentdb.git", from: "2.4.3")
]
```

...and depend on `KurrentDB` in the targets that use it:

<!-- snippet:skip -->
```swift
.target(
    name: "MyApp",
    dependencies: [.product(name: "KurrentDB", package: "swift-kurrentdb")]
)
```

To share clients across several independent KurrentDB instances, also depend on `KurrentDBPool`; see <doc:Client-pools>.

## Connection string

[Official reference](https://docs.kurrent.io/clients/grpc/getting-started.html#connection-string)

The connection string has the following format:

```
kurrentdb+discover://admin:changeit@cluster.dns.name:2113
```

`cluster.dns.name` is a DNS A record that points to every cluster node; `+discover` tells the client to discover the cluster through it.

Alternatively, list the cluster nodes separated by commas, without `+discover`. The client uses them as gossip seeds:

```
kurrentdb://admin:changeit@node1.dns.name:2113,node2.dns.name:2113,node3.dns.name:2113
```

With a single host and no `+discover`, the client connects to that node directly. The schemes `kurrentdb`, `kurrent`, `kdb` and `esdb` are interchangeable, as are their `+discover` forms.

There are a number of query parameters that can be used in the connection string to instruct the cluster how and where the connection should be established. All query parameters are optional.

|Parameter|Accepted values|Default|Description|
|:--------|:-------------:|:-----:|-----------|
|tls|  true | true |Use secure connection, set to false when connecting to a non-secure server or cluster.|
| ^ | false |   ^  |     ^     |
|connectionName|String|None|Connection name|
|maxDiscoverAttempts|Number|10|Number of attempts to discover the cluster.|
|discoveryInterval|Number|100|Cluster discovery polling interval in milliseconds.|
|gossipTimeout|Number|3|Gossip timeout in seconds, when the gossip call times out, it will be retried.|
|nodePreference|leader|leader|Preferred node role. When creating a client for write operations, always use leader.|
| ^ | follower |   ^  |     ^     |
| ^ | random |   ^  |     ^     |
| ^ | readOnlyReplica |   ^  |     ^     |
|tlsVerifyCert|true|true|In secure mode, set to true when using an untrusted connection to the node if you don't have the CA file available. Don't use in production.|
| ^ | false |   ^  |     ^     |
|tlsCaFile|String|None|Path to the CA file when connecting to a secure cluster with a certificate that's not signed by a trusted CA. If the file cannot be read, `parse` throws instead of trusting the system's root certificates.|
| ^ | file path |   ^  |     ^     |
|defaultDeadline|Number|None|Default deadline, in milliseconds, for calls that complete before they return — appends, deletes, management calls, `read()`. Subscriptions and `read().lazy` are not bounded by it; a `CallOptions.timeout` set on the client wins.|
|keepAliveInterval|Number|10|Interval between keep-alive ping calls, in seconds.|
|keepAliveTimeout|Number|10|Keep-alive ping call timeout, in seconds.|
|userCertFile|String|None|User certificate file (PEM) for X.509 authentication. Requires TLS.|
| ^ | file path |   ^  |     ^     |
|userKeyFile|String|None|Key file (PEM) for the user certificate used for X.509 authentication. Requires TLS.|
| ^ | file path |   ^  |     ^     |

Parameter names and the scheme are case-insensitive. A parameter the client does not know, a parameter given twice, or a value it cannot use (for example `tls=yes` or `gossipTimeout=0`) makes `ClientSettings.parse(connectionString:policy:)` throw; the error names the parameter, never its value.

Connection strings are parsed strictly according to RFC 3986 (`policy: .rfc3986`, which the overloads of `parse(connectionString:)` and `fromEnv(key:)` without `policy:` use). The username, the password and parameter values are percent-decoded. In credentials only letters, digits and ``-._~!$&'()*+,;=:`` may be written as they are; in parameter names and values only letters, digits and ``-._~!$'()*+,;:/?`` (and `=` in values) may. Everything else must be percent-encoded — in credentials that includes `@`, `/`, `?`, `#` and `%`; in parameter values `@` (write `%40`), `#` and `%`. Whitespace, non-ASCII characters and control characters must be encoded everywhere, so a `tlsCaFile` path with spaces or backslashes is written with `%20` / `%5C`. Leading and trailing whitespace and newlines around the whole string are ignored. The simplest way to encode a password is to encode all of it:

```swift
let password = "p@ss/w%rd#1"
let encoded = password.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed)!
let parsed = try ClientSettings.parse(connectionString: "kurrentdb://admin:\(encoded)@localhost:2113", policy: .rfc3986)
```

If a password can contain arbitrary characters, skip the connection string for it and set the credentials with the builder instead:

```swift
let settings = ClientSettings.localhost()
    .authenticated(.credentials(username: "admin", password: "p@ss/w%rd#1"))
```

When connecting to an insecure instance, specify `tls=false` parameter. For example, for a node running locally use `kurrentdb://localhost:2113?tls=false`. Note that `usernames` and `passwords` aren't provided there because insecure deployments don't support authentication and authorisation.



## Client Settings

### Connection string

You can build client settings by parsing a connection string.

```swift
let settings: ClientSettings = try .parse(connectionString: "kurrentdb://admin:changeit@localhost:2113")
```

Or you can use a string literal directly:

```swift
let settings: ClientSettings = "kurrentdb://admin:changeit@localhost:2113"
```

### Environment variable

Use `fromEnv(key:policy:)` to build client settings from a connection string stored in an environment variable. This keeps connection details out of source code, which is useful for containerized deployments and CI.

```swift
// Reads the connection string from SWIFT_KURRENT_DB_URL (the default key)
let fromDefaultKey = try ClientSettings.fromEnv()

// Or read from a custom environment variable
let fromCustomKey = try ClientSettings.fromEnv(key: "MY_KURRENTDB_URL")
```

`fromEnv(key:policy:)` defaults to ``DEFAULT_ENV_KEY_NAME`` (`"SWIFT_KURRENT_DB_URL"`) and parses the variable's value the same way as `parse(connectionString:policy:)`. It throws `KurrentError.internalParsingError` if the variable is unset or the connection string is malformed.

### Localhost (development)

Use the `localhost()` factory method for local development. You can specify one or more ports for multi-node local clusters:

```swift
// Single node on default port (2113)
let single = ClientSettings.localhost()

// Single node on custom port
let customPort = ClientSettings.localhost(ports: 2114)

// Multi-node local cluster
let cluster = ClientSettings.localhost(ports: 2111, 2112, 2113)
```

### Remote endpoints

Use `remote()` for production deployments. TLS is enabled by default via the `secure` parameter:

```swift
// Single remote node (secure by default)
let single = ClientSettings.remote(.init(host: "db.example.com", port: 2113))

// Multi-node cluster
let cluster = ClientSettings.remote(
    .init(host: "node1.example.com", port: 2113),
    .init(host: "node2.example.com", port: 2113),
    .init(host: "node3.example.com", port: 2113)
)

// Explicitly disable TLS for insecure remote connections
let insecure = ClientSettings.remote("db.example.com:2113", secure: false)
```

### Endpoint string literals

``Endpoint`` conforms to `ExpressibleByStringLiteral`, so you can use string literals in `"host:port"` format:

```swift
let withPort = ClientSettings.remote("db.example.com:2113")

// Port defaults to 2113 if omitted
let defaultPort = ClientSettings.remote("db.example.com")
```

### Fluent configuration

``ClientSettings`` uses a builder pattern for additional configuration. Chain methods to customize TLS, authentication, certificates, and other options:

```swift
let settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
    .secure(true)
    .tlsVerifyCert(false)
    .authenticated(.credentials(username: "admin", password: "changeit"))
    .certificate(source: .crtInBundle("ca")!)
```

Available builder methods:

| Method | Description |
|--------|-------------|
| `.secure(_:)` | Enable or disable TLS |
| `.tlsVerifyCert(_:)` | Enable or disable TLS certificate verification |
| `.authenticated(_:)` | Set authentication credentials |
| `.certificate(source:)` | Add a TLS certificate source |
| `.certificate(path:fallback:)` | Add a CA certificate from a file. `fallback: .none` throws when the file cannot be read; `fallback: .systemTrustRoots` leaves it out, so the system roots are trusted if no other CA is configured (only for configurations shared with environments that legitimately have no CA file) |
| `.connectionName(_:)` | Set a connection name |
| `.defaultDeadline(_:)` | Default deadline (ms) for calls that complete before they return; not subscriptions or `.lazy` reads |
| `.keepAlive(_:)` | Configure keep-alive settings |
| `.discoveryInterval(_:)` | Set cluster discovery polling interval |
| `.maxDiscoveryAttempts(_:)` | Set maximum cluster discovery attempts |

### Parameterized initialization

You can also configure all options at initialization time:

```swift
let settings = ClientSettings(
    clusterMode: .seeds([
        .init(host: "node1.example.com", port: 2113),
        .init(host: "node2.example.com", port: 2113)
    ]),
    nodePreference: .leader,
    gossipTimeout: .seconds(3),
    secure: true,
    tlsVerifyCert: false,
    keepAlive: .init(intervalMs: 10000, timeoutMs: 10000),
    authentication: .credentials(username: "admin", password: "changeit")
)
```

### Cluster modes

| Mode | Description |
|------|-------------|
| `.standalone(endpoint)` | Single node connection |
| `.dns(domain)` | DNS-based cluster discovery |
| `.seeds([endpoints])` | Gossip-based cluster discovery with seed nodes |

### Leader changes and retries

A cluster elects a new leader whenever the current one restarts, resigns or loses contact with the other nodes. An election takes a few seconds, and during that window:

- Leader-only commands (appends, deletes, persistent-subscription management) sent to the old leader are rejected. The server answers with gRPC status `UNAVAILABLE` and the metadata `exception: not-leader`; the client surfaces this as ``KurrentError/grpcConnectionError(cause:)``.
- Reads keep working: a demoted node still serves them. A `.lazy` read that is already streaming is not retried — only establishing the call is.
- `grpcConnectionError`, `grpcError`, `grpcRuntimeError`, `deadlineExceeded` and `notLeaderException` count as node failures. For those, the client drops the cached node, rediscovers the leader through gossip and retries the operation according to ``ClientSettings/operationRetryPolicy``.

The default policy is **2 attempts with no delay** — one immediate retry. That covers the common case where the new leader is already elected when the first call fails. If the election is still in progress when the retry runs, the error reaches your code:

```swift
do {
    try await client.streams(specified: "orders").append(events: [eventData]) {
        $0.expectedRevision = .streamExists
    }
} catch KurrentError.grpcConnectionError(let cause) {
    // The leader moved and the retry policy was exhausted.
    // `cause.metadata` carries `exception: not-leader` when the node rejected the command.
    print("append failed while the cluster was electing a leader: \(cause)")
}
```

To ride out an election inside the client instead, opt into a policy with backoff. ``OperationRetryPolicy/default`` makes 3 attempts with 100 ms initial delay, 2× backoff, a 10 s cap and full jitter; or build your own:

```swift
let resilient = ClientSettings.localhost()
    .operationRetryPolicy(.default)

let custom = ClientSettings.localhost()
    .operationRetryPolicy(OperationRetryPolicy(
        maxAttempts: 5,
        initialDelay: .milliseconds(200),
        maxDelay: .seconds(30),
        multiplier: 1.5,
        jitter: .full
    ))
```

Set an `expectedRevision` on appends you let the client retry: if a connection drops after the leader applied the write but before the response arrived, the retry is then rejected with ``KurrentError/wrongExpectedVersion(expected:current:)`` instead of appending the events twice.

## Authentication

Credentials set on ``ClientSettings`` are sent with every call:

```swift
// Username and password
let basic = ClientSettings.localhost()
    .authenticated(.credentials(username: "admin", password: "changeit"))

// Bearer token, e.g. an OAuth/OIDC access token
let bearer = ClientSettings.localhost()
    .authenticated(.bearer(token: "eyJhbGciOi..."))
```

With a client certificate (X.509), the client presents the certificate during the TLS handshake instead of sending an `Authorization` header. It needs a TLS connection, and it can only be set for the whole client, not per call. When `userCertFile` and `userKeyFile` are present, username and password in the connection string are ignored.

```swift
let x509: ClientSettings = try .parse(
    connectionString: "kurrentdb://node1:2113?tlsCaFile=/certs/ca.crt&userCertFile=/certs/user.crt&userKeyFile=/certs/user.key"
)
```

To use different credentials for a single call — for example, the end user's token in a multi-tenant service — call `authenticated(_:)` on the value you make the call through. The override applies only to calls made through the returned value; the client's own credentials are unchanged:

```swift
try await client.streams(specified: "orders")
    .authenticated(.bearer(token: "user-access-token"))
    .append(events: [eventData])

let details = try await client.projections(of: .anyMode)
    .authenticated(.credentials(username: "ops", password: "secret"))
    .list()
```

`Streams`, `Projections`, `PersistentSubscriptions`, `Users`, `Operations` and `Monitoring` all support `authenticated(_:)`.

## Creating a client
First, create a client and get it connected to the database.

```swift
let settings = ClientSettings.localhost()
    .authenticated(.credentials(username: "admin", password: "changeit"))
let client = KurrentDBClient(settings: settings)
```

### Reusing the client

Create one client per application and share it. The client manages its connections for you:

- Calls that complete before they return — appends, deletes, stream metadata, reads of a stream or of `$all`, projection statistics, user details, projection and user management, server operations — share one connection per node and its HTTP/2 stream budget. A shared connection that has been idle for an hour is closed and reopened on next use.
- Calls that hand you a live stream — subscriptions, persistent subscriptions, server statistics — each open their own connection, which closes when the stream ends or is cancelled. Long-lived subscriptions therefore never compete with other calls for capacity on a shared connection.

Calling `shutdown()` closes every connection the client opened, ends active subscriptions, and makes every later call — including calls through `Streams` or other values obtained from the client earlier — throw `KurrentError.connectionClosed`. Shutdown is initiated rather than awaited: connections may still be closing when the method returns. Calling it more than once has no further effect.

```swift
try client.shutdown()
```


## Creating an event

An ``EventData`` payload can be any `Codable` type; it's stored as JSON.

> Note: User-defined server-side projections require events serialized as JSON. The examples in this documentation use JSON.

<!-- snippet:toplevel -->
```swift
struct TestEvent: Codable, Sendable {
    let id: String
    let note: String
}
```

```swift
let eventData = EventData(
    eventType: "TestEvent",
    model: TestEvent(id: UUID().uuidString, note: "I wrote my first event!")
)
```

Choose a stable event type name rather than deriving it from the Swift type name; renaming the type later would otherwise change how stored events are identified.

## Appending events

Each event has a unique ID (`UUID`). The database uses it to make writes idempotent, which only works when you also state the stream revision you expect.

Append the event to the stream `some-stream`:

```swift
let appendResponse = try await client.streams(specified: "some-stream").append(events: [eventData]) {
    $0.expectedRevision = .any
}
```

This appends without checking whether the stream exists or what revision it's at. See <doc:Appending-events> for more.

## Reading events

Read the events back from `some-stream`:

```swift
let responses = try await client.streams(specified: "some-stream").read {
    $0.revision = .start
    $0.limit = 10
}

for try await response in responses {
    let readEvent = try response.event
    let testEvent = try readEvent.record.decode(to: TestEvent.self)
    print(testEvent as Any)
}
```

Each response carries a ``ReadEvent``; its `record` holds the event, whose payload you decode with `decode(to:)`. See <doc:Reading-events> for more.
