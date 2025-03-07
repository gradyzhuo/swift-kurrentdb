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

You can build a client settings for a single node configuration by parsing a connection string.

```swift
let settings: ClientSettings = .parse(connectionString: "esdb://admin:changeit@localhost:2113")
```

or you can also build it with a string literal, like:
```swift
let settings: ClientSettings = "esdb://admin:changeit@localhost:2113".parse()

// or using string literal directly.
let settings: ClientSettings = "esdb://admin:changeit@localhost:2113"
```

You can use a convenience static method in development mode to connect to `localhost`.

```swift
// settings with credentials
let settings: ClientSettings = .localhost(userCredentials: .init(username: "admin", 
                                                                   password: "changeit")

//settings with credentials with adding ssl file by path
let settings: ClientSettings = .localhost(userCredentials: .init(username: "admin", 
                                                                            password: "changeit"), 
                                                                 trustRoots: .file("...filePath..."))

//or add ssl file with bundle
let settings: ClientSettings = .localhost(userCredentials: .init(username: "admin", 
                                                                 password: "changeit"), 
                                                                 trustRoots: .fileInBundle(forResource: "ca", 
                                                                                           withExtension: "crt", 
                                                                                        inBundle: .main))
```


## Creating a client
First, create a client and get it connected to the database.

```swift
let settings: ClientSettings = .localhost()
let client = KurrentDBClient(settings: settings)
let stream = client.streams(of: .specified("some-stream"))
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
try await stream.append(
    events: [eventData], 
    options: .init().revision(expected: .any))
```

Here we are appending events without checking if the stream exists or if the stream version matches the expected event version. See more advanced scenarios in appending [events documentation](https://docs.kurrent.io/clients/grpc/appending-events.html).



## Reading events
Finally, we can read events back from the `some-stream` stream.


```swift
// Read events from stream.
let responses = try await stream.read(cursor: .start, options: .init().set(limit: 10))

// loop it.
for try await response in responses {
    if let .event(readEvent) = response.content{
        //handle event
    }
}
```

When you read events from the stream, you get a collection of `ResolvedEvent` structures. The event payload is returned as a byte array and needs to be deserialized. See more advanced scenarios in [reading events documentation](https://docs.kurrent.io/clients/grpc/reading-events.html).


