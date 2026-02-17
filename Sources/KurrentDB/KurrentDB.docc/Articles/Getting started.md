# Getting started
Get started by connecting your application to EventStoreDB.


## Getting the library

### Swift Package Manager

The Swift Package Manager is the preferred way to get EventStoreDB. Simply add the package dependency to your Package.swift:

```swift
dependencies: [
  .package(url: "https://github.com/gradyzhuo/eventstoredb-swift.git", from: "1.0.0")
]
```
...and depend on "KurrentDB" in the necessary targets:

```swift
.target(
  name: ...,
  dependencies: [.product(name: "KurrentDB", package: "eventstoredb-swift")]
]
```


## Connection string
[Official Reference](https://docs.kurrent.io/clients/grpc/getting-started.html#connection-string)
The connection string has the following format:

```
esdb+discover://admin:changeit@cluster.dns.name:2113
```

There, `cluster.dns.name` is the name of a DNS A record that points to all the cluster nodes. Alternatively, you can list cluster nodes separated by comma instead of the cluster DNS name:

```
esdb+discover://admin:changeit@node1.dns.name:2113,node2.dns.name:2113,node3.dns.name:2113
```

There are a number of query parameters that can be used in the connection string to instruct the cluster how and where the connection should be established. All query parameters are optional.

|Parameter|Accepted values|Default|Description|
|:--------|:-------------:|:-----:|-----------|
|tls|  true | true |Use secure connection, set to false when connecting to a non-secure server or cluster.|
| ^ | false |   ^  |     ^     |
|connectionName|String|None|Connection name|
|maxDiscoverAttempts|Number|10|Number of attempts to discover the cluster.|
|discoveryInterval|Number|100|Cluster discovery polling interval in milliseconds.|
|gossipTimeout|Number|5|Gossip timeout in seconds, when the gossip call times out, it will be retried.|
|nodePreference|leader|leader|Preferred node role. When creating a client for write operations, always use leader.|
| ^ | follower |   ^  |     ^     |
| ^ | random |   ^  |     ^     |
| ^ | readOnlyReplica |   ^  |     ^     |
|tlsVerifyCert|true|true|In secure mode, set to true when using an untrusted connection to the node if you don't have the CA file available. Don't use in production.|
| ^ | false |   ^  |     ^     |
|tlsCaFile|String|None|Path to the CA file when connecting to a secure cluster with a certificate that's not signed by a trusted CA.|
| ^ | file path |   ^  |     ^     |
|defaultDeadline|Number|None|Default timeout for client operations, in milliseconds. Most clients allow overriding the deadline per operation.|
|keepAliveInterval|Number|10|Interval between keep-alive ping calls, in seconds.|
|keepAliveTimeout|Number|10|Keep-alive ping call timeout, in seconds.|
|userCertFile|String|None|User certificate file for X.509 authentication.|
| ^ | file path |   ^  |     ^     |
|userKeyFile|String|None|Key file for the user certificate used for X.509 authentication.|
| ^ | file path |   ^  |     ^     |

When connecting to an insecure instance, specify `tls=false` parameter. For example, for a node running locally use `esdb://localhost:2113?tls=false`. Note that `usernames` and `passwords` aren't provided there because insecure deployments don't support authentication and authorisation.



## Client Settings

### Connection string

You can build client settings by parsing a connection string.

```swift
let settings: ClientSettings = try .parse(connectionString: "esdb://admin:changeit@localhost:2113")
```

Or you can use a string literal directly:

```swift
let settings: ClientSettings = "kurrent://admin:changeit@localhost:2113"
```

### Localhost (development)

Use the `localhost()` factory method for local development. You can specify one or more ports for multi-node local clusters:

```swift
// Single node on default port (2113)
let settings = ClientSettings.localhost()

// Single node on custom port
let settings = ClientSettings.localhost(ports: 2114)

// Multi-node local cluster
let settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
```

### Remote endpoints

Use `remote()` for production deployments. TLS is enabled by default via the `secure` parameter:

```swift
// Single remote node (secure by default)
let settings = ClientSettings.remote(.init(host: "db.example.com", port: 2113))

// Multi-node cluster
let settings = ClientSettings.remote(
    .init(host: "node1.example.com", port: 2113),
    .init(host: "node2.example.com", port: 2113),
    .init(host: "node3.example.com", port: 2113)
)

// Explicitly disable TLS for insecure remote connections
let settings = ClientSettings.remote("db.example.com:2113", secure: false)
```

### Endpoint string literals

``Endpoint`` conforms to `ExpressibleByStringLiteral`, so you can use string literals in `"host:port"` format:

```swift
let settings = ClientSettings.remote("db.example.com:2113")

// Port defaults to 2113 if omitted
let settings = ClientSettings.remote("db.example.com")
```

### Fluent configuration

``ClientSettings`` uses a builder pattern for additional configuration. Chain methods to customize TLS, authentication, certificates, and other options:

```swift
let settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
    .secure(true)
    .tlsVerifyCert(false)
    .authenticated(.credentials(username: "admin", password: "changeit"))
    .cerificate(source: .crtInBundle("ca", inBundle: .module)!)
```

Available builder methods:

| Method | Description |
|--------|-------------|
| `.secure(_:)` | Enable or disable TLS |
| `.tlsVerifyCert(_:)` | Enable or disable TLS certificate verification |
| `.authenticated(_:)` | Set authentication credentials |
| `.cerificate(source:)` | Add a TLS certificate source |
| `.cerificate(path:)` | Add a TLS certificate from a file path |
| `.connectionName(_:)` | Set a connection name |
| `.defaultDeadline(_:)` | Set default operation timeout |
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
    secure: true,
    tlsVerifyCert: false,
    nodePreference: .leader,
    gossipTimeout: .seconds(5),
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


## Creating a client
First, create a client and get it connected to the database.

```swift
let settings = ClientSettings.localhost()
    .authenticated(.credentials(username: "admin", password: "changeit"))
let client = KurrentDBClient(settings: settings)
```


## Creating an event
In `Swift`, the payload in EventData conforms to the Codable protocol, which means you can use any type that can be encoded or decoded to `JSON`.

> Server-side projections: User-defined server-side projections require events to be serialized in JSON format.
>
>`KurrentDB` use JSON for serialization in the documentation examples.

### Using a string as the payload
```swift
let eventData = EventData(
    id: UUID(),
    eventType: "TestEvent",
    payload: "I wrote my first event!"
)
```

### Using a customized event model as the payload
```swift
struct TestEvent: Codable {
    let id: String
    let note: String
}

let eventModel = TestEvent(
    id: UUID().uuidString
    note: "I wrote my first event!"
)

let eventData = EventData(
    id: UUID(),
    eventType: "\(TestEvent.self)", //eventType from structure type.
    payload: eventModel
)
```


## Appending Event
Each event in the database has its own unique identifier (UUID). The database uses it to ensure idempotent writes, but it only works if you specify the stream revision when appending events to the stream.

In the snippet below, we append the event to the stream `some-stream`.

```swift
let appendResponse = try await client.appendStream("some-stream", events: [eventData]) {
    $0.revision(expected: .any)
}
```

Here we are appending events without checking if the stream exists or if the stream version matches the expected event version. See more advanced scenarios in appending [events documentation](https://docs.kurrent.io/clients/grpc/appending-events.html).



## Reading events
Finally, we can read events back from the `some-stream` stream.


```swift

// Read events from stream.
let responses = try await client.readStream("some-stream") {
    $0
    .startFrom(revision: .end)
    .limit(10)
}

// loop it.
for try await response in responses {
    if let readEvent = try response.event{
        //handle event
    }
}
```

When you read events from the stream, you get a collection of `ResolvedEvent` structures. The event payload is returned as a byte array and needs to be deserialized. See more advanced scenarios in [reading events documentation](https://docs.kurrent.io/clients/grpc/reading-events.html).


