# ``KurrentDB``

@Options(scope: local) {
    @TopicsVisualStyle(hidden)
}

The Kurrent Database Client SDK connected by `gRPC`.

## Articles 
- <doc:Getting-started>
- <doc:Appending-events>
- <doc:Reading-events>
- <doc:Projections>
- <doc:User-management>
- <doc:Persistent-subscriptions>
- <doc:Server-operations>

## Architecture
- <doc:StreamsTarget-design>
- <doc:ProjectionsTarget-design>
- <doc:PersistentSubscriptionTarget-design>
- <doc:UsersTarget-design>
- <doc:OperationsTarget-design>

## Usage

Create a ``KurrentDBClient`` instance with client settings and the number of threads.
Then, interact with a specific stream by creating a `Streams` client for it.

### Streams
```swift
let clientSettings: ClientSettings = "kurrent://localhost:2113?tls=false" // Initialize with actual settings
let client = KurrentDBClient(settings: clientSettings, numberOfThreads: 2)

// Perform an action like appending events to the stream
try await client.appendStream("streamName", events: eventData)

```

### PersistentSubscriptions

```swift
// Import packages of EventStoreDB.
import KurrentDB

// Using a client settings for a single node configuration by parsing a connection string.
let settings: ClientSettings = .localhost()

// Build a persistentSubscriptions client.
let client = KurrentDBClient(settings: settings)

// the stream identifier to subscribe.
let streamIdentifier = StreamIdentifier(name: UUID().uuidString)

// the group of subscription
let groupName = "myGroupTest"

let streamName = UUID().uuidString
try await client.createPersistentSubscription(stream: streamName, groupName: groupName)

let subscription = try await client.subscribePersistentSubscription(stream: streamName, groupName: groupName)

// Loop all results by subscription.events
for try await result in subscription.events {
    //handle result
    // ...
    
    // ack the readEvent if succeed
    try await subscription.ack(readEvents: result.event)
    // else nack thr readEvent if not succeed.
    // try await subscription.nack(readEvents: result.event, action: .park, reason: "It's failed.")
}

```


